#!/bin/bash

###
# Скрипт для проверки статуса шардирования и репликации
###

echo "=== Проверка статуса MongoDB кластера ==="

echo "1. Статус шардирования:"
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.status()
EOF

echo -e "\n2. Статус репликации Shard 1:"
docker compose exec -T shard1_replica1 mongosh --port 27018 --quiet <<EOF
rs.status()
EOF

echo -e "\n3. Статус репликации Shard 2:"
docker compose exec -T shard2_replica1 mongosh --port 27020 --quiet <<EOF
rs.status()
EOF

echo -e "\n4. Распределение данных по шардам:"
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.getShardDistribution()
EOF

echo -e "\n5. Проверка Redis:"
docker compose exec -T redis redis-cli ping

echo -e "\n6. Статистика Redis:"
docker compose exec -T redis redis-cli info memory | grep -E "(used_memory|used_memory_peak|keyspace_hits|keyspace_misses)"

echo -e "\n=== Проверка завершена ===" 