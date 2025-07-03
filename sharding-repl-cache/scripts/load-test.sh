#!/bin/bash

###
# Скрипт для тестирования производительности системы
###

echo "=== Тест производительности MongoDB кластера ==="

# Количество запросов для теста
REQUESTS=100
CONCURRENT=10

echo "1. Тест чтения данных (с кешированием):"
echo "Выполняется $REQUESTS запросов с $CONCURRENT параллельными соединениями..."

# Тест чтения с кешированием
for i in $(seq 1 $REQUESTS); do
    curl -s "http://localhost:8080/helloDoc/users" > /dev/null &
    
    # Ограничиваем количество параллельных запросов
    if (( i % CONCURRENT == 0 )); then
        wait
    fi
done
wait

echo "Тест чтения завершен!"

echo -e "\n2. Тест записи данных:"
echo "Создание $REQUESTS новых пользователей..."

# Тест записи
for i in $(seq 1 $REQUESTS); do
    curl -s -X POST "http://localhost:8080/helloDoc/users" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"load_test_user_$i\", \"age\": $((RANDOM % 50 + 18))}" > /dev/null &
    
    if (( i % CONCURRENT == 0 )); then
        wait
    fi
done
wait

echo "Тест записи завершен!"

echo -e "\n3. Проверка распределения новых данных:"
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.getShardDistribution()
EOF

echo -e "\n4. Статистика кеширования:"
docker compose exec -T redis redis-cli info stats | grep -E "(keyspace_hits|keyspace_misses|total_commands_processed)"

echo -e "\n=== Тест производительности завершен ===" 