# MongoDB Sharding Project

## Описание

Данный проект демонстрирует реализацию шардирования MongoDB для повышения производительности и масштабируемости системы. Архитектура включает:

- **Config Server**: Хранение метаданных о распределении данных
- **Mongos Router**: Маршрутизация запросов к шардам
- **Shard 1**: Первый шард на порту 27018
- **Shard 2**: Второй шард на порту 27019
- **API Application**: FastAPI приложение для работы с данными

## Запуск проекта

### 1. Запуск сервисов

```bash
docker compose up -d
```

### 2. Ожидание запуска

Подождите 30-60 секунд для полного запуска всех сервисов MongoDB.

## Инициализация шардирования

### Шаг 1: Инициализация Config Server Replica Set

```bash
docker compose exec -T config1 mongosh --port 27017 --quiet <<EOF
rs.initiate({
  _id: 'configReplSet',
  configsvr: true,
  members: [
    { _id: 0, host: 'config1:27017' }
  ]
})
EOF
```

### Шаг 2: Инициализация Shard 1 Replica Set

```bash
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: 'shard1ReplSet',
  members: [
    { _id: 0, host: 'shard1:27018' }
  ]
})
EOF
```

### Шаг 3: Инициализация Shard 2 Replica Set

```bash
docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: 'shard2ReplSet',
  members: [
    { _id: 0, host: 'shard2:27019' }
  ]
})
EOF
```

### Шаг 4: Ожидание синхронизации

Подождите 30 секунд для синхронизации replica sets:

```bash
sleep 30
```

### Шаг 5: Добавление шардов в кластер

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard('shard1ReplSet/shard1:27018')
sh.addShard('shard2ReplSet/shard2:27019')
EOF
```

### Шаг 6: Включение шардирования для базы данных

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
sh.enableSharding('somedb')
EOF
```

### Шаг 7: Настройка ключа шардирования для коллекции

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
sh.shardCollection('somedb.helloDoc', { '_id': 'hashed' })
EOF
```

### Шаг 8: Заполнение базы данных тестовыми данными

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
for(var i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({
    age: i, 
    name: 'user' + i,
    email: 'user' + i + '@example.com',
    created_at: new Date()
  })
}
EOF
```

## Проверка работы

### Проверка статуса шардирования

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.status()
EOF
```

### Проверка количества документов в каждом шарде

**Shard 1:**
```bash
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

**Shard 2:**
```bash
docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

### Проверка общего количества документов через API

Откройте в браузере: http://localhost:8080

Или выполните:
```bash
curl http://localhost:8080/somedb/count
```

## Автоматизация инициализации

Для автоматической инициализации всех шагов используйте готовый скрипт:

```bash
chmod +x init-sharding.sh
./init-sharding.sh
```

## Остановка проекта

```bash
docker compose down -v
```

## Полезные команды

### Просмотр логов
```bash
docker compose logs -f mongos
docker compose logs -f shard1
docker compose logs -f shard2
```

### Подключение к MongoDB
```bash
# К mongos router
docker compose exec -T mongos mongosh --port 27017

# К shard1
docker compose exec -T shard1 mongosh --port 27018

# К shard2
docker compose exec -T shard2 mongosh --port 27019
``` 