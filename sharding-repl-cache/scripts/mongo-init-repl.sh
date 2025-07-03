#!/bin/bash

# Скрипт инициализации MongoDB с шардированием и репликацией
# Для онлайн-магазина "Мобильный мир"

set -e

echo "🚀 Инициализация MongoDB с шардированием и репликацией..."

# Функция для ожидания готовности MongoDB
wait_for_mongo() {
    local host=$1
    local port=$2
    local max_attempts=30
    local attempt=1
    
    echo "⏳ Ожидание готовности MongoDB на $host:$port..."
    
    while [ $attempt -le $max_attempts ]; do
        if docker compose exec -T $host mongosh --port $port --quiet --eval "db.adminCommand('ping')" > /dev/null 2>&1; then
            echo "✅ MongoDB на $host:$port готов"
            return 0
        fi
        
        echo "   Попытка $attempt/$max_attempts..."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    echo "❌ MongoDB на $host:$port не готов после $max_attempts попыток"
    return 1
}

# Ожидание готовности всех сервисов
echo "📋 Ожидание готовности всех сервисов..."

wait_for_mongo "config1" "27019"
wait_for_mongo "config2" "27019"
wait_for_mongo "config3" "27019"

wait_for_mongo "shard1_replica1" "27018"
wait_for_mongo "shard1_replica2" "27018"
wait_for_mongo "shard1_replica3" "27018"

wait_for_mongo "shard2_replica1" "27020"
wait_for_mongo "shard2_replica2" "27020"
wait_for_mongo "shard2_replica3" "27020"

echo "✅ Все сервисы готовы"

# Инициализация Config Server репликации
echo "🔄 Инициализация Config Server репликации..."
docker compose exec -T config1 mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "configReplSet",
  configsvr: true,
  members: [
    { _id: 0, host: "config1:27019" },
    { _id: 1, host: "config2:27019" },
    { _id: 2, host: "config3:27019" }
  ]
})
EOF

echo "⏳ Ожидание готовности Config Server репликации..."
sleep 10

# Проверка статуса Config Server репликации
echo "📊 Проверка статуса Config Server репликации..."
docker compose exec -T config1 mongosh --port 27019 --quiet <<EOF
rs.status()
EOF

# Ожидание готовности mongos
echo "⏳ Ожидание готовности mongos..."
sleep 10
wait_for_mongo "mongos" "27017"

# Инициализация репликации для Shard 1
echo "🔄 Инициализация репликации для Shard 1..."
docker compose exec -T shard1_replica1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1ReplSet",
  members: [
    { _id: 0, host: "shard1_replica1:27018", priority: 2 },
    { _id: 1, host: "shard1_replica2:27018", priority: 1 },
    { _id: 2, host: "shard1_replica3:27018", priority: 1 }
  ]
})
EOF

# Инициализация репликации для Shard 2
echo "🔄 Инициализация репликации для Shard 2..."
docker compose exec -T shard2_replica1 mongosh --port 27020 --quiet <<EOF
rs.initiate({
  _id: "shard2ReplSet",
  members: [
    { _id: 0, host: "shard2_replica1:27020", priority: 2 },
    { _id: 1, host: "shard2_replica2:27020", priority: 1 },
    { _id: 2, host: "shard2_replica3:27020", priority: 1 }
  ]
})
EOF

# Ожидание готовности репликации
echo "⏳ Ожидание готовности репликации..."
sleep 15

# Проверка статуса репликации
echo "📊 Проверка статуса репликации Shard 1..."
docker compose exec -T shard1_replica1 mongosh --port 27018 --quiet <<EOF
rs.status()
EOF

echo "📊 Проверка статуса репликации Shard 2..."
docker compose exec -T shard2_replica1 mongosh --port 27020 --quiet <<EOF
rs.status()
EOF

# Добавление шардов в кластер
echo "🔗 Добавление шардов в кластер..."

# Добавление Shard 1
echo "➕ Добавление Shard 1..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1ReplSet/shard1_replica1:27018,shard1_replica2:27018,shard1_replica3:27018")
EOF

# Добавление Shard 2
echo "➕ Добавление Shard 2..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard2ReplSet/shard2_replica1:27020,shard2_replica2:27020,shard2_replica3:27020")
EOF

# Создание базы данных и коллекции
echo "🗄️ Создание базы данных и коллекции..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.createCollection("helloDoc")
EOF

# Включение шардирования для базы данных
echo "⚙️ Включение шардирования для базы данных..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { "name": "hashed" })
EOF

# Загрузка тестовых данных
echo "📝 Загрузка тестовых данных..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.insertMany([
  { name: "iPhone 15", price: 999, category: "smartphone", stock: 50 },
  { name: "Samsung Galaxy S24", price: 899, category: "smartphone", stock: 45 },
  { name: "Google Pixel 8", price: 699, category: "smartphone", stock: 30 },
  { name: "iPad Pro", price: 1099, category: "tablet", stock: 25 },
  { name: "MacBook Air", price: 1199, category: "laptop", stock: 20 },
  { name: "AirPods Pro", price: 249, category: "accessories", stock: 100 },
  { name: "Apple Watch", price: 399, category: "wearable", stock: 60 },
  { name: "Sony WH-1000XM5", price: 349, category: "headphones", stock: 40 },
  { name: "Nintendo Switch", price: 299, category: "gaming", stock: 35 },
  { name: "DJI Mini 3", price: 459, category: "drone", stock: 15 }
])
EOF

# Проверка распределения данных
echo "📊 Проверка распределения данных по шардам..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.getShardDistribution()
EOF

# Проверка статуса шардирования
echo "📋 Финальная проверка статуса шардирования..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.status()
EOF

echo "🎉 Инициализация завершена успешно!"
echo ""
echo "📋 Что было настроено:"
echo "   ✅ Config Server репликация (3 реплики)"
echo "   ✅ Репликация для Shard 1 (3 реплики)"
echo "   ✅ Репликация для Shard 2 (3 реплики)"
echo "   ✅ Добавление шардов в кластер"
echo "   ✅ Создание базы данных 'somedb'"
echo "   ✅ Включение шардирования по полю 'name'"
echo "   ✅ Загрузка тестовых данных"
echo ""
echo "🌐 API доступен по адресу: http://localhost:8080"
echo "📚 Swagger документация: http://localhost:8080/docs"
echo ""
echo "🔍 Для проверки статуса выполните: ./scripts/check-status.sh"
echo "⚡ Для нагрузочного теста выполните: ./scripts/load-test.sh"
