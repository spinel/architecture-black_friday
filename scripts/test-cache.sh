#!/bin/bash

# Скрипт тестирования производительности кеширования
# Для проекта "Мобильный мир" с Redis кешированием

echo "🧪 Тестирование производительности кеширования"
echo "================================================"

# Проверка доступности API
echo "📋 Проверка доступности API..."
if ! curl -s http://localhost:8080/ > /dev/null; then
    echo "❌ API недоступен. Убедитесь, что сервисы запущены: docker compose up -d"
    exit 1
fi
echo "✅ API доступен"

# Проверка количества документов
echo ""
echo "📊 Проверка количества документов..."
DOC_COUNT=$(curl -s http://localhost:8080/helloDoc/count | jq -r '.items_count')
echo "📈 Общее количество документов: $DOC_COUNT"

if [ "$DOC_COUNT" -lt 1000 ]; then
    echo "⚠️  Внимание: количество документов меньше 1000. Рекомендуется запустить инициализацию: ./scripts/mongo-init-repl.sh"
else
    echo "✅ Количество документов соответствует требованиям (≥1000)"
fi

# Тестирование производительности
echo ""
echo "⚡ Тестирование производительности кеширования..."
echo ""

# Первый запрос (должен быть медленным)
echo "🔄 Первый запрос (без кеша)..."
START_TIME=$(date +%s%N)
curl -s http://localhost:8080/helloDoc/users > /dev/null
END_TIME=$(date +%s%N)
FIRST_REQUEST_TIME=$(( (END_TIME - START_TIME) / 1000000 ))
echo "⏱️  Время выполнения: ${FIRST_REQUEST_TIME}мс"

# Небольшая пауза
sleep 2

# Повторный запрос (должен быть быстрым благодаря кешу)
echo ""
echo "🔄 Повторный запрос (с кешем)..."
START_TIME=$(date +%s%N)
curl -s http://localhost:8080/helloDoc/users > /dev/null
END_TIME=$(date +%s%N)
SECOND_REQUEST_TIME=$(( (END_TIME - START_TIME) / 1000000 ))
echo "⏱️  Время выполнения: ${SECOND_REQUEST_TIME}мс"

# Анализ результатов
echo ""
echo "📊 Анализ результатов:"
echo "======================"

if [ "$SECOND_REQUEST_TIME" -lt 100 ]; then
    echo "✅ Повторный запрос выполняется <100мс (${SECOND_REQUEST_TIME}мс)"
    echo "✅ Кеширование работает корректно"
else
    echo "❌ Повторный запрос выполняется ≥100мс (${SECOND_REQUEST_TIME}мс)"
    echo "❌ Кеширование может работать некорректно"
fi

SPEEDUP=$((FIRST_REQUEST_TIME / SECOND_REQUEST_TIME))
echo "🚀 Ускорение: в ${SPEEDUP} раз быстрее"

# Проверка Redis
echo ""
echo "🔍 Проверка Redis..."
if docker compose exec -T redis redis-cli ping > /dev/null 2>&1; then
    echo "✅ Redis работает"
    
    # Проверка кешированных ключей
    CACHE_KEYS=$(docker compose exec -T redis redis-cli keys "api:cache:*" | wc -l)
    echo "📦 Кешированных ключей: $CACHE_KEYS"
    
    if [ "$CACHE_KEYS" -gt 0 ]; then
        echo "✅ Кеш содержит данные"
    else
        echo "⚠️  Кеш пуст"
    fi
else
    echo "❌ Redis недоступен"
fi

# Информация о системе
echo ""
echo "📋 Информация о системе..."
SYSTEM_INFO=$(curl -s http://localhost:8080/)
echo "🗄️  Топология MongoDB: $(echo $SYSTEM_INFO | jq -r '.mongo_topology_type')"
echo "🔗 Количество шардов: $(echo $SYSTEM_INFO | jq -r '.shards | length')"
echo "⚡ Кеширование включено: $(echo $SYSTEM_INFO | jq -r '.cache_enabled')"

echo ""
echo "🎉 Тестирование завершено!"
echo ""
echo "💡 Для дополнительной информации:"
echo "   - Swagger UI: http://localhost:8080/docs"
echo "   - Статус системы: http://localhost:8080/"
echo "   - Проверка статуса: ./scripts/check-status.sh" 