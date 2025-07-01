#!/bin/bash

echo "🚀 Инициализация шардированной MongoDB..."

# Функция для проверки готовности сервиса
wait_for_service() {
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

# Ждем запуска всех сервисов
echo "⏳ Ожидание запуска сервисов..."
sleep 30

# Проверяем готовность всех сервисов
wait_for_service "config1" "27017" || exit 1
wait_for_service "shard1" "27018" || exit 1
wait_for_service "shard2" "27019" || exit 1

# Шаг 1: Инициализация Config Server Replica Set
echo "📋 Инициализация Config Server..."
docker compose exec -T config1 mongosh --port 27017 --quiet --eval "
rs.initiate({
  _id: 'configReplSet',
  configsvr: true,
  members: [
    { _id: 0, host: 'config1:27017' }
  ]
})
"

# Ждем инициализации config server
echo "⏳ Ожидание инициализации Config Server..."
sleep 30

# Шаг 2: Инициализация Shard 1 Replica Set
echo "🔧 Инициализация Shard 1..."
docker compose exec -T shard1 mongosh --port 27018 --quiet --eval "
rs.initiate({
  _id: 'shard1ReplSet',
  members: [
    { _id: 0, host: 'shard1:27018' }
  ]
})
"

# Шаг 3: Инициализация Shard 2 Replica Set
echo "🔧 Инициализация Shard 2..."
docker compose exec -T shard2 mongosh --port 27019 --quiet --eval "
rs.initiate({
  _id: 'shard2ReplSet',
  members: [
    { _id: 0, host: 'shard2:27019' }
  ]
})
"

# Ждем синхронизации replica sets
echo "⏳ Ожидание синхронизации replica sets..."
sleep 60

# Ждем готовности mongos
echo "⏳ Ожидание готовности mongos..."
wait_for_service "mongos" "27017" || exit 1

# Шаг 4: Добавление шардов в кластер через mongos
echo "🔗 Добавление шардов в кластер..."
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "
sh.addShard('shard1ReplSet/shard1:27018')
sh.addShard('shard2ReplSet/shard2:27019')
"

# Ждем добавления шардов
sleep 30

# Шаг 5: Включение шардирования для базы данных
echo "📊 Включение шардирования для базы данных..."
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "
use somedb
sh.enableSharding('somedb')
"

# Шаг 6: Настройка ключа шардирования для коллекции
echo "🔑 Настройка ключа шардирования..."
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "
use somedb
sh.shardCollection('somedb.helloDoc', { '_id': 'hashed' })
"

# Шаг 7: Заполнение базы данных тестовыми данными
echo "📝 Заполнение базы данных тестовыми данными..."
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "
use somedb
for(var i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({
    age: i, 
    name: 'user' + i,
    email: 'user' + i + '@example.com',
    created_at: new Date()
  })
}
"

# Проверка статуса шардирования
echo "✅ Проверка статуса шардирования..."
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "
sh.status()
"

echo "🎉 Инициализация шардированной MongoDB завершена!"
echo "📊 Статус кластера можно проверить по адресу: http://localhost:8080" 