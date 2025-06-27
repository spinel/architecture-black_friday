# Архитектура MongoDB с шардированием, репликацией и кешированием

## Описание проекта

Данный проект демонстрирует реализацию высоконагруженной архитектуры MongoDB для онлайн-магазина "Мобильный мир" с использованием:

- **Шардирования MongoDB** - для горизонтального масштабирования
- **Репликации** - для отказоустойчивости (3 реплики на шард)
- **Кеширования Redis** - для ускорения доступа к данным
- **API Gateway** - для балансировки нагрузки

## Структура проекта

Проект содержит три варианта реализации:

1. **`mongo-sharding/`** - Базовая реализация шардирования (2 шарда)
2. **`mongo-sharding-repl/`** - Шардирование с репликацией (3 реплики на шард)
3. **`sharding-repl-cache/`** - **ФИНАЛЬНАЯ РЕАЛИЗАЦИЯ** - Шардирование + репликация + кеширование Redis

## Запуск финальной реализации

Для проверки работы ревьюером используется директория `sharding-repl-cache/`, которая включает все три задания.

### Шаг 1: Переход в директорию проекта

```bash
cd sharding-repl-cache
```

### Шаг 2: Запуск всех сервисов

```bash
docker compose up -d
```

### Шаг 3: Проверка статуса сервисов

```bash
docker compose ps
```

Должны быть запущены следующие сервисы:
- `config1`, `config2`, `config3` - Config Server реплика-сет
- `shard1_1`, `shard1_2`, `shard1_3` - Первый шард (3 реплики)
- `shard2_1`, `shard2_2`, `shard2_3` - Второй шард (3 реплики)
- `mongos` - Маршрутизатор запросов
- `redis` - Кеш-сервер
- `pymongo_api` - API приложение

### Шаг 4: Инициализация шардирования и репликации

```bash
chmod +x init-sharding-repl.sh
./init-sharding-repl.sh
```

Этот скрипт автоматически выполнит:
- Инициализацию Config Server реплика-сета
- Инициализацию реплика-сетов для каждого шарда
- Добавление шардов в кластер
- Включение шардирования для базы данных
- Настройку ключа шардирования
- Заполнение тестовыми данными

### Шаг 5: Проверка работы приложения

Откройте в браузере: **http://localhost:8080**

Или выполните:
```bash
curl http://localhost:8080
```

## Доступные эндпоинты API

### Основная информация
- `GET /` - Информация о MongoDB и статус кеша
- `GET /status` - Статус шардирования
- `GET /shards` - Информация о шардах

### Работа с данными
- `GET /{database}/{collection}/count` - Количество документов в коллекции
- `GET /{database}/{collection}/users` - Получение пользователей (с кешированием)
- `POST /{database}/{collection}/users` - Добавление пользователя

### Проверка кеширования
- `GET /cache/status` - Статус Redis кеша
- `GET /cache/stats` - Статистика использования кеша

## Проверка шардирования

### Статус шардирования
```bash
docker compose exec mongos mongosh --port 27017 --quiet --eval "sh.status()"
```

### Количество документов в каждом шарде
```bash
# Shard 1
docker compose exec shard1_1 mongosh --port 27018 --quiet --eval "use somedb; db.helloDoc.countDocuments()"

# Shard 2
docker compose exec shard2_1 mongosh --port 27019 --quiet --eval "use somedb; db.helloDoc.countDocuments()"
```

### Проверка репликации
```bash
# Статус реплика-сета Shard 1
docker compose exec shard1_1 mongosh --port 27018 --quiet --eval "rs.status()"

# Статус реплика-сета Shard 2
docker compose exec shard2_1 mongosh --port 27019 --quiet --eval "rs.status()"
```

## Проверка кеширования

### Статус Redis
```bash
docker compose exec redis redis-cli ping
```

### Статистика кеша
```bash
docker compose exec redis redis-cli info memory
```

### Тест кеширования
1. Выполните запрос: `curl http://localhost:8080/somedb/helloDoc/users`
2. Повторите запрос - второй запрос должен быть быстрее благодаря кешу
3. Проверьте статистику: `curl http://localhost:8080/cache/stats`

## Остановка проекта

```bash
docker compose down -v
```

## Полезные команды

### Просмотр логов
```bash
# Логи API приложения
docker compose logs -f pymongo_api

# Логи MongoDB
docker compose logs -f mongos

# Логи Redis
docker compose logs -f redis
```

### Подключение к сервисам
```bash
# К mongos router
docker compose exec mongos mongosh --port 27017

# К Redis
docker compose exec redis redis-cli

# К API контейнеру
docker compose exec pymongo_api bash
```

## Архитектурные схемы

В корне проекта находятся схемы архитектуры в формате draw.io:
- `architecture-schema-v1-sharding.drawio` - Базовая схема шардирования
- `architecture-schema-v2-replication.drawio` - Шардирование с репликацией
- `architecture-schema-v3-caching.drawio` - Шардирование с репликацией и кешированием
- `architecture-schema-v4-scaling.drawio` - Горизонтальное масштабирование
- `architecture-schema-v5-cdn.drawio` - CDN для статического контента

## Технические детали

### Используемые образы
- **MongoDB**: `dh-mirror.gitverse.ru/mongo:latest`
- **Redis**: `redis:alpine`
- **API**: `kazhem/pymongo_api:1.0.0` (собирается из Dockerfile)

### Порты
- **API**: 8080
- **MongoDB**: 27017 (mongos), 27018 (shard1), 27019 (shard2)
- **Redis**: 6379

### Переменные окружения
- `MONGODB_URL`: `mongodb://mongos:27017`
- `MONGODB_DATABASE_NAME`: `somedb`
- `REDIS_URL`: `redis://redis:6379`

## Требования к системе

- Docker
- Docker Compose
- Минимум 4GB RAM
- 10GB свободного места на диске