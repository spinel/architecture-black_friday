#!/bin/bash

# Скрипт инициализации MongoDB с шардированием и репликацией
# Для онлайн-магазина "Мобильный мир" с кешированием

set -e

echo "🚀 Инициализация MongoDB с шардированием, репликацией и кешированием..."

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

wait_for_mongo "shard1_1" "27018"
wait_for_mongo "shard1_2" "27018"
wait_for_mongo "shard1_3" "27018"

wait_for_mongo "shard2_1" "27020"
wait_for_mongo "shard2_2" "27020"
wait_for_mongo "shard2_3" "27020"

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
docker compose exec -T shard1_1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1ReplSet",
  members: [
    { _id: 0, host: "shard1_1:27018", priority: 2 },
    { _id: 1, host: "shard1_2:27018", priority: 1 },
    { _id: 2, host: "shard1_3:27018", priority: 1 }
  ]
})
EOF

# Инициализация репликации для Shard 2
echo "🔄 Инициализация репликации для Shard 2..."
docker compose exec -T shard2_1 mongosh --port 27020 --quiet <<EOF
rs.initiate({
  _id: "shard2ReplSet",
  members: [
    { _id: 0, host: "shard2_1:27020", priority: 2 },
    { _id: 1, host: "shard2_2:27020", priority: 1 },
    { _id: 2, host: "shard2_3:27020", priority: 1 }
  ]
})
EOF

# Ожидание готовности репликации
echo "⏳ Ожидание готовности репликации..."
sleep 15

# Проверка статуса репликации
echo "📊 Проверка статуса репликации Shard 1..."
docker compose exec -T shard1_1 mongosh --port 27018 --quiet <<EOF
rs.status()
EOF

echo "📊 Проверка статуса репликации Shard 2..."
docker compose exec -T shard2_1 mongosh --port 27020 --quiet <<EOF
rs.status()
EOF

# Добавление шардов в кластер
echo "🔗 Добавление шардов в кластер..."

# Добавление Shard 1
echo "➕ Добавление Shard 1..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1ReplSet/shard1_1:27018,shard1_2:27018,shard1_3:27018")
EOF

# Добавление Shard 2
echo "➕ Добавление Shard 2..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard2ReplSet/shard2_1:27020,shard2_2:27020,shard2_3:27020")
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

# Загрузка тестовых данных (≥1000 документов)
echo "📝 Загрузка тестовых данных (≥1000 документов)..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb

// Создаем массив с большим количеством тестовых данных
var products = [
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
];

// Создаем массив для массовой вставки
var bulkData = [];

// Генерируем 1000+ документов
for (var i = 0; i < 1000; i++) {
  var product = products[i % products.length];
  var variant = Math.floor(i / products.length) + 1;
  
  bulkData.push({
    name: product.name + " " + variant,
    price: product.price + (variant * 10),
    category: product.category,
    stock: Math.max(1, product.stock - (variant * 2)),
    sku: "SKU-" + (i + 1000),
    description: "Вариант " + variant + " продукта " + product.name,
    rating: (Math.random() * 2 + 3).toFixed(1), // Рейтинг от 3.0 до 5.0
    reviews: Math.floor(Math.random() * 100),
    inStock: Math.random() > 0.3 // 70% товаров в наличии
  });
}

// Вставляем данные
db.helloDoc.insertMany(bulkData);

// Добавляем еще несколько уникальных товаров для разнообразия
var additionalProducts = [
  { name: "Xiaomi 14", price: 799, category: "smartphone", stock: 30 },
  { name: "OnePlus 12", price: 899, category: "smartphone", stock: 25 },
  { name: "Surface Pro", price: 1299, category: "tablet", stock: 15 },
  { name: "Dell XPS 13", price: 1399, category: "laptop", stock: 12 },
  { name: "Bose QC45", price: 329, category: "headphones", stock: 50 },
  { name: "PlayStation 5", price: 499, category: "gaming", stock: 20 },
  { name: "GoPro Hero 11", price: 399, category: "camera", stock: 30 },
  { name: "Fitbit Sense", price: 299, category: "wearable", stock: 40 },
  { name: "Kindle Paperwhite", price: 139, category: "ereader", stock: 60 },
  { name: "Echo Dot", price: 49, category: "smart_home", stock: 80 }
];

db.helloDoc.insertMany(additionalProducts);
EOF

# Проверка количества документов
echo "📊 Проверка количества документов..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
print("Общее количество документов: " + db.helloDoc.countDocuments({}));
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
echo "   ✅ Загрузка ≥1000 тестовых документов"
echo "   ✅ Redis кеширование настроено"
echo ""
echo "🌐 API доступен по адресу: http://localhost:8080"
echo "📚 Swagger документация: http://localhost:8080/docs"
echo ""
echo "🔍 Для проверки статуса выполните: ./scripts/check-status.sh"
echo "⚡ Для нагрузочного теста выполните: ./scripts/load-test.sh"
echo ""
echo "💡 Для тестирования кеширования:"
echo "   Первый запрос: curl http://localhost:8080/helloDoc/users (медленный)"
echo "   Повторный запрос: curl http://localhost:8080/helloDoc/users (быстрый, <100мс)" 