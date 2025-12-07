#!/bin/bash
# ============================================================
# Dify Dokploy 部署修复脚本
# 作者：天才少女哈雷酱
# 用途：在 Dokploy 部署 Dify 完成后运行此脚本修复所有问题
# ============================================================

set -e

echo "🚀 =================================================="
echo "   Dify Dokploy 部署修复脚本"
echo "   作者：天才少女哈雷酱 (￣▽￣)b"
echo "=================================================="
echo ""

# 获取 stack 名称
STACK_NAME=$(docker ps --filter "name=api" --format "{{.Names}}" | grep -oP "stack-[a-z0-9]+" | head -1)

if [ -z "$STACK_NAME" ]; then
    echo "❌ 未找到 Dify 容器，请先在 Dokploy 中部署"
    exit 1
fi

echo "📦 检测到 Stack 名称: $STACK_NAME"
echo ""

# ============================================================
# 步骤 1: 修复存储权限
# ============================================================
echo "🔧 [1/5] 修复存储权限..."

API_STORAGE=$(docker volume inspect ${STACK_NAME}_api_storage 2>/dev/null | grep Mountpoint | awk -F'"' '{print $4}')
if [ -n "$API_STORAGE" ]; then
    sudo chmod -R 777 "$API_STORAGE"
    sudo chown -R 1000:1000 "$API_STORAGE"
    echo "   ✅ api_storage 权限已修复: $API_STORAGE"
fi

PLUGIN_STORAGE=$(docker volume inspect ${STACK_NAME}_plugin_daemon_storage 2>/dev/null | grep Mountpoint | awk -F'"' '{print $4}')
if [ -n "$PLUGIN_STORAGE" ]; then
    sudo chmod -R 777 "$PLUGIN_STORAGE"
    sudo chown -R 1000:1000 "$PLUGIN_STORAGE"
    echo "   ✅ plugin_daemon_storage 权限已修复: $PLUGIN_STORAGE"
fi

echo ""

# ============================================================
# 步骤 2: 创建 Plugin 数据库
# ============================================================
echo "🗄️ [2/5] 创建 Plugin 数据库..."

docker exec ${STACK_NAME}-db-1 psql -U postgres -c "CREATE DATABASE dify_plugin;" 2>/dev/null && \
    echo "   ✅ dify_plugin 数据库已创建" || \
    echo "   ℹ️ dify_plugin 数据库已存在"

echo ""

# ============================================================
# 步骤 3: 删除旧的 Plugin Daemon 容器
# ============================================================
echo "🗑️ [3/5] 删除旧的 Plugin Daemon 容器..."

docker rm -f ${STACK_NAME}-plugin_daemon-1 2>/dev/null && \
    echo "   ✅ 旧容器已删除" || \
    echo "   ℹ️ 没有找到旧容器"

echo ""

# ============================================================
# 步骤 4: 创建新的 Plugin Daemon 容器
# ============================================================
echo "🆕 [4/5] 创建新的 Plugin Daemon 容器..."

docker run -d \
  --name ${STACK_NAME}-plugin_daemon-1 \
  --network ${STACK_NAME}_default \
  --network-alias plugin_daemon \
  --restart always \
  -e DB_USERNAME=postgres \
  -e DB_PASSWORD=difyai123456 \
  -e DB_HOST=db \
  -e DB_PORT=5432 \
  -e DB_DATABASE=dify_plugin \
  -e REDIS_HOST=redis \
  -e REDIS_PORT=6379 \
  -e REDIS_PASSWORD=difyai123456 \
  -e SERVER_PORT=5002 \
  -e "SERVER_KEY=lYkiYYT6owG+71oLerGzA7GXCgOT++6ovaezWAjpCjf+Sjc3ZtU+qUEi" \
  -e MAX_PLUGIN_PACKAGE_SIZE=52428800 \
  -e PPROF_ENABLED=false \
  -e DIFY_INNER_API_URL=http://api:5001 \
  -e "DIFY_INNER_API_KEY=QaHbTe77CtuXmsfyhR7+vRjI/+XbV1AaFy691iy+kGDv2Jvy0/eAh8Y1" \
  -e PLUGIN_REMOTE_INSTALLING_HOST=0.0.0.0 \
  -e PLUGIN_REMOTE_INSTALLING_PORT=5003 \
  -e PLUGIN_WORKING_PATH=/app/storage/cwd \
  -e FORCE_VERIFYING_SIGNATURE=false \
  -e PYTHON_ENV_INIT_TIMEOUT=120 \
  -e "ENDPOINT_URL_TEMPLATE=http://api:5001/e/{hook_id}" \
  -e PLUGIN_STORAGE_TYPE=local \
  -e PLUGIN_STORAGE_LOCAL_ROOT=/app/storage \
  -e PLATFORM=local \
  -v ${STACK_NAME}_plugin_daemon_storage:/app/storage \
  langgenius/dify-plugin-daemon:0.4.1-local > /dev/null

echo "   ✅ Plugin Daemon 容器已创建"
echo ""

# ============================================================
# 步骤 5: 重启 API 服务
# ============================================================
echo "🔄 [5/5] 重启 API 服务..."
sleep 5
docker restart ${STACK_NAME}-api-1 > /dev/null
echo "   ✅ API 服务已重启"
echo ""

# ============================================================
# 检查最终状态
# ============================================================
echo "📊 等待服务启动..."
sleep 5

echo ""
echo "============================================================"
echo "   🎉 修复完成！容器状态："
echo "============================================================"
docker ps --filter "name=${STACK_NAME}" --format "table {{.Names}}\t{{.Status}}"

echo ""
echo "============================================================"
echo "   检查 Plugin Daemon 日志："
echo "============================================================"
docker logs ${STACK_NAME}-plugin_daemon-1 --tail 5 2>&1

echo ""
echo "============================================================"
echo "   ✅ 所有修复步骤已完成！"
echo "   请访问你的 Dify 域名进行测试"
echo "   如有问题，查看日志：docker logs ${STACK_NAME}-api-1"
echo "============================================================"

