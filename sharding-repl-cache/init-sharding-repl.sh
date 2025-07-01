#!/bin/bash

echo "🚀 Инициализация шардированной MongoDB с репликацией и кешированием..."

# Функция для проверки готовности сервиса MongoDB
wait_for_mongo_service() {
    local service_name=$1
    local port=$2
    local max_attempts=30
    local attempt=1
    
    echo "⏳ Ожидание готовности $service_name на порту $port..."
    
    while [ $attempt -le $max_attempts ]; do
        if docker compose exec -T $service_name mongosh --port $port --quiet --eval "db.adminCommand('ping')" > /dev/null 2>&1; then
            echo "✅ $service_name готов к работе"
            return 0
        fi
        
        echo "🔄 Попытка $attempt/$max_attempts - $service_name еще не готов..."
        sleep 10
        attempt=$((attempt + 1))
    done
    
    echo "❌ $service_name не готов после $max_attempts попыток"
    return 1
}

# Функция для проверки готовности Redis
wait_for_redis_service() {
    local service_name=$1
    local max_attempts=30
    local attempt=1
    
    echo "⏳ Ожидание готовности $service_name..."
    
    while [ $attempt -le $max_attempts ]; do
        if docker compose exec -T $service_name redis-cli ping > /dev/null 2>&1; then
            echo "✅ $service_name готов к работе"
            return 0
        fi
        
        echo "🔄 Попытка $attempt/$max_attempts - $service_name еще не готов..."
        sleep 10
        attempt=$((attempt + 1))
    done
    
    echo "❌ $service_name не готов после $max_attempts попыток"
    return 1
}

echo "⏳ Ожидание запуска сервисов..."

# Ждем запуска всех сервисов
sleep 30

# Проверяем готовность всех сервисов MongoDB
wait_for_mongo_service "config1" "27017" || exit 1
wait_for_mongo_service "config2" "27017" || exit 1
wait_for_mongo_service "config3" "27017" || exit 1
wait_for_mongo_service "shard1_1" "27018" || exit 1
wait_for_mongo_service "shard1_2" "27018" || exit 1
wait_for_mongo_service "shard1_3" "27018" || exit 1
wait_for_mongo_service "shard2_1" "27019" || exit 1
wait_for_mongo_service "shard2_2" "27019" || exit 1
wait_for_mongo_service "shard2_3" "27019" || exit 1

# Проверяем готовность Redis
wait_for_redis_service "redis" || exit 1

echo "📋 Инициализация Config Server Replica Set..."

# Инициализация Config Server Replica Set
docker compose exec -T config1 mongosh --port 27017 --quiet --eval "
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

# Ждем инициализации config server
echo "⏳ Ожидание инициализации Config Server..."
sleep 30

echo "🔧 Инициализация Shard 1 Replica Set..."

# Инициализация Shard 1 Replica Set
docker compose exec -T shard1_1 mongosh --port 27018 --quiet --eval "
rs.initiate({
  _id: 'shard1ReplSet',
  members: [
    { _id: 0, host: 'shard1_1:27018' },
    { _id: 1, host: 'shard1_2:27018' },
    { _id: 2, host: 'shard1_3:27018' }
  ]
})
"

echo "🔧 Инициализация Shard 2 Replica Set..."

# Инициализация Shard 2 Replica Set
docker compose exec -T shard2_1 mongosh --port 27019 --quiet --eval "
rs.initiate({
  _id: 'shard2ReplSet',
  members: [
    { _id: 0, host: 'shard2_1:27019' },
    { _id: 1, host: 'shard2_2:27019' },
    { _id: 2, host: 'shard2_3:27019' }
  ]
})
"

echo "⏳ Ожидание синхронизации replica sets..."
sleep 60

# Ждем готовности mongos
echo "⏳ Ожидание готовности mongos..."
wait_for_mongo_service "mongos" "27017" || exit 1

echo "🔗 Добавление шардов в кластер..."

# Добавление шардов в кластер через mongos
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "
sh.addShard('shard1ReplSet/shard1_1:27018,shard1_2:27018,shard1_3:27018')
sh.addShard('shard2ReplSet/shard2_1:27019,shard2_2:27019,shard2_3:27019')
"

# Ждем добавления шардов
sleep 30

echo "📊 Включение шардирования для базы данных..."

# Включение шардирования для базы данных
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "
use somedb
sh.enableSharding('somedb')
"

echo "🔑 Настройка ключа шардирования..."

# Настройка ключа шардирования
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "
use somedb
sh.shardCollection('somedb.helloDoc', { _id: 'hashed' })
"

echo "📝 Заполнение базы данных тестовыми данными..."

# Заполнение базы данных тестовыми данными
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "
use somedb
for (let i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({
    _id: i,
    message: 'Hello from sharded cluster with replication and caching!',
    timestamp: new Date(),
    shard: 'shard' + (i % 2 + 1)
  })
}
"

echo "✅ Проверка статуса шардирования..."

# Проверка статуса шардирования
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "
sh.status()
"

echo "🎉 Инициализация шардированной MongoDB с репликацией и кешированием завершена!"
echo "📊 Статус кластера можно проверить по адресу: http://localhost:8080"
echo "🔍 Статус кеша можно проверить по адресу: http://localhost:8080/cache/status" 