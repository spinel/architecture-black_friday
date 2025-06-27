#!/bin/bash

echo "🚀 Инициализация шардированной MongoDB..."

# Ждем запуска всех сервисов
echo "⏳ Ожидание запуска сервисов..."
sleep 30

# Шаг 1: Инициализация Config Server Replica Set
echo "📋 Инициализация Config Server..."
docker compose exec -T config1 mongosh --port 27017 --quiet <<EOF
rs.initiate({
  _id: 'configReplSet',
  configsvr: true,
  members: [
    { _id: 0, host: 'config1:27017' }
  ]
})
EOF

# Шаг 2: Инициализация Shard 1 Replica Set
echo "🔧 Инициализация Shard 1..."
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: 'shard1ReplSet',
  members: [
    { _id: 0, host: 'shard1:27018' }
  ]
})
EOF

# Шаг 3: Инициализация Shard 2 Replica Set
echo "🔧 Инициализация Shard 2..."
docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: 'shard2ReplSet',
  members: [
    { _id: 0, host: 'shard2:27019' }
  ]
})
EOF

# Ждем синхронизации replica sets
echo "⏳ Ожидание синхронизации replica sets..."
sleep 30

# Шаг 4: Добавление шардов в кластер через mongos
echo "🔗 Добавление шардов в кластер..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard('shard1ReplSet/shard1:27018')
sh.addShard('shard2ReplSet/shard2:27019')
EOF

# Шаг 5: Включение шардирования для базы данных
echo "📊 Включение шардирования для базы данных..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
sh.enableSharding('somedb')
EOF

# Шаг 6: Настройка ключа шардирования для коллекции
echo "🔑 Настройка ключа шардирования..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
sh.shardCollection('somedb.helloDoc', { '_id': 'hashed' })
EOF

# Шаг 7: Заполнение базы данных тестовыми данными
echo "📝 Заполнение базы данных тестовыми данными..."
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

# Проверка статуса шардирования
echo "✅ Проверка статуса шардирования..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.status()
EOF

echo "🎉 Инициализация шардированной MongoDB завершена!"
echo "📊 Статус кластера можно проверить по адресу: http://localhost:8080" 