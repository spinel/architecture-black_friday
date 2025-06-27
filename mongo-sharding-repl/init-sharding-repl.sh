#!/bin/bash

echo "🚀 Инициализация шардированной MongoDB с репликацией..."
echo "⏳ Ожидание запуска сервисов..."

# Ждем запуска всех сервисов
sleep 30

echo "📋 Инициализация Config Server Replica Set..."

# Инициализация Config Server Replica Set
mongosh --host config1:27017 --eval "
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

echo "🔧 Инициализация Shard 1 Replica Set..."

# Инициализация Shard 1 Replica Set
mongosh --host shard1_1:27018 --eval "
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
mongosh --host shard2_1:27019 --eval "
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
sleep 30

echo "🔗 Добавление шардов в кластер..."

# Добавление шардов в кластер через mongos
mongosh --host mongos:27017 --eval "
sh.addShard('shard1ReplSet/shard1_1:27018,shard1_2:27018,shard1_3:27018')
sh.addShard('shard2ReplSet/shard2_1:27019,shard2_2:27019,shard2_3:27019')
"

echo "📊 Включение шардирования для базы данных..."

# Включение шардирования для базы данных
mongosh --host mongos:27017 --eval "
use somedb
sh.enableSharding('somedb')
"

echo "🔑 Настройка ключа шардирования..."

# Настройка ключа шардирования
mongosh --host mongos:27017 --eval "
use somedb
sh.shardCollection('somedb.helloDoc', { _id: 'hashed' })
"

echo "📝 Заполнение базы данных тестовыми данными..."

# Заполнение базы данных тестовыми данными
mongosh --host mongos:27017 --eval "
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

echo "✅ Проверка статуса шардирования..."

# Проверка статуса шардирования
mongosh --host mongos:27017 --eval "
sh.status()
"

echo "🎉 Инициализация шардированной MongoDB с репликацией завершена!"
echo "📊 Статус кластера можно проверить по адресу: http://localhost:8080" 