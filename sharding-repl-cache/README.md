# MongoDB Шардирование с Репликацией

Этот проект демонстрирует настройку MongoDB с шардированием и репликацией для повышения производительности и отказоустойчивости.

## Архитектура

Проект реализует второй вариант схемы архитектуры:
- **Config Server**: 3 реплики (config1, config2, config3)
- **Shard 1**: 3 реплики (shard1_1, shard1_2, shard1_3)
- **Shard 2**: 3 реплики (shard2_1, shard2_2, shard2_3)
- **Mongos Router**: маршрутизатор запросов
- **API Application**: FastAPI приложение

## Запуск проекта

### 1. Запуск контейнеров

```bash
docker compose up -d
```

Это запустит:
- 3 config сервера
- 6 шардов (по 3 реплики на шард)
- mongos роутер
- API приложение

### 2. Инициализация шардирования и репликации

После запуска контейнеров выполните скрипт инициализации:

```bash
./init-sharding-repl.sh
```

Этот скрипт автоматически выполнит:
- Инициализацию Config Server Replica Set
- Инициализацию Shard 1 Replica Set (3 реплики)
- Инициализацию Shard 2 Replica Set (3 реплики)
- Добавление шардов в кластер
- Включение шардирования для базы данных
- Настройку ключа шардирования
- Заполнение тестовыми данными (1000 документов)

### 3. Проверка статуса

Проверить статус кластера можно через mongosh:

```bash
docker exec -it mongos mongosh --eval "sh.status()"
```

### 4. Проверка API

API доступно по адресу: http://localhost:8080

Эндпоинты:
- `GET /somedb/count` - общее количество документов
- `GET /somedb/shard-count` - количество документов в каждом шарде
- `GET /somedb/replica-count` - количество реплик

## Ручная настройка (если скрипт не работает)

### 1. Инициализация Config Server Replica Set

```bash
docker exec -it config1 mongosh --eval "
rs.initiate({
  _id: 'configReplSet',
  configsvr: true,
  members: [
    { _id: 0, host: 'config1:27017' },
    { _id: 1, host: 'config2:27017' },
    { _id: 2, host: 'config3:27017' }
  ]
})
"
```

### 2. Инициализация Shard 1 Replica Set

```bash
docker exec -it shard1_1 mongosh --port 27018 --eval "
rs.initiate({
  _id: 'shard1ReplSet',
  members: [
    { _id: 0, host: 'shard1_1:27018' },
    { _id: 1, host: 'shard1_2:27018' },
    { _id: 2, host: 'shard1_3:27018' }
  ]
})
"
```

### 3. Инициализация Shard 2 Replica Set

```bash
docker exec -it shard2_1 mongosh --port 27019 --eval "
rs.initiate({
  _id: 'shard2ReplSet',
  members: [
    { _id: 0, host: 'shard2_1:27019' },
    { _id: 1, host: 'shard2_2:27019' },
    { _id: 2, host: 'shard2_3:27019' }
  ]
})
"
```

### 4. Добавление шардов в кластер

```bash
docker exec -it mongos mongosh --eval "
sh.addShard('shard1ReplSet/shard1_1:27018,shard1_2:27018,shard1_3:27018')
sh.addShard('shard2ReplSet/shard2_1:27019,shard2_2:27019,shard2_3:27019')
"
```

### 5. Включение шардирования

```bash
docker exec -it mongos mongosh --eval "
use somedb
sh.enableSharding('somedb')
sh.shardCollection('somedb.helloDoc', { _id: 'hashed' })
"
```

### 6. Заполнение тестовыми данными

```bash
docker exec -it mongos mongosh --eval "
use somedb
for (let i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({
    _id: i,
    message: 'Hello from sharded cluster with replication!',
    timestamp: new Date(),
    shard: 'shard' + (i % 2 + 1)
  })
}
"
```

## Проверка работы

### Проверка количества документов

```bash
curl http://localhost:8080/somedb/count
```

### Проверка распределения по шардам

```bash
curl http://localhost:8080/somedb/shard-count
```

### Проверка количества реплик

```bash
curl http://localhost:8080/somedb/replica-count
```

### Проверка статуса репликации

```bash
# Config Server
docker exec -it config1 mongosh --eval "rs.status()"

# Shard 1
docker exec -it shard1_1 mongosh --port 27018 --eval "rs.status()"

# Shard 2
docker exec -it shard2_1 mongosh --port 27019 --eval "rs.status()"
```

## Остановка проекта

```bash
docker compose down
```

Для полной очистки с удалением данных:

```bash
docker compose down -v
```

## Структура проекта

```
mongo-sharding-repl/
├── compose.yaml              # Docker Compose конфигурация
├── init-sharding-repl.sh     # Скрипт инициализации
├── README.md                 # Документация
└── api_app/                  # API приложение
    ├── app.py
    ├── Dockerfile
    └── requirements.txt
```

## Требования

- Docker
- Docker Compose
- mongosh (для ручной настройки)

## Примечания

- Все replica sets настроены с автоматическим выбором primary
- Данные распределяются между шардами по хешированному ключу `_id`
- API приложение подключается к mongos роутеру
- Для production рекомендуется настроить аутентификацию и SSL 