#!/bin/bash

###
# Инициализация шардирования MongoDB
###

echo "Ожидание запуска сервисов..."
sleep 30

echo "1. Инициализация Config Server репликации..."
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

echo "2. Инициализация Shard1 репликации..."
docker compose exec -T shard1_replica1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1ReplSet",
  members: [
    { _id: 0, host: "shard1_replica1:27018" },
    { _id: 1, host: "shard1_replica2:27018" },
    { _id: 2, host: "shard1_replica3:27018" }
  ]
})
EOF

echo "3. Инициализация Shard2 репликации..."
docker compose exec -T shard2_replica1 mongosh --port 27020 --quiet <<EOF
rs.initiate({
  _id: "shard2ReplSet",
  members: [
    { _id: 0, host: "shard2_replica1:27020" },
    { _id: 1, host: "shard2_replica2:27020" },
    { _id: 2, host: "shard2_replica3:27020" }
  ]
})
EOF

echo "4. Ожидание готовности репликаций..."
sleep 30

echo "5. Добавление шардов в кластер..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1ReplSet/shard1_replica1:27018,shard1_replica2:27018,shard1_replica3:27018")
sh.addShard("shard2ReplSet/shard2_replica1:27020,shard2_replica2:27020,shard2_replica3:27020")
EOF

echo "6. Создание базы данных и коллекции..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.createCollection("helloDoc")
EOF

echo "7. Включение шардирования для коллекции..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", {"name": "hashed"})
EOF

echo "8. Загрузка тестовых данных..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i})
EOF

echo "9. Проверка статуса шардирования..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.status()
EOF

echo "Инициализация завершена!"

