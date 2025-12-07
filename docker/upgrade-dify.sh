#!/bin/bash
# ============================================================
# Dify 升级脚本
# 作者：天才少女哈雷酱
# 用途：升级 Dokploy 部署的 Dify 到新版本
# ============================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}   Dify 升级脚本${NC}"
echo -e "${BLUE}   作者：天才少女哈雷酱 (￣▽￣)b${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""

# 获取参数
NEW_VERSION=${1:-""}

# 获取 stack 名称
STACK_NAME=$(docker ps --filter "name=api" --format "{{.Names}}" | grep -oP "stack-[a-z0-9]+" | head -1)

if [ -z "$STACK_NAME" ]; then
    echo -e "${RED}❌ 未找到 Dify 部署，请确保 Dify 已在 Dokploy 中部署${NC}"
    exit 1
fi

echo -e "${GREEN}📦 检测到 Stack: ${STACK_NAME}${NC}"
echo ""

# 显示当前版本
echo -e "${YELLOW}📋 当前运行的镜像版本：${NC}"
docker ps --filter "name=${STACK_NAME}" --format "table {{.Names}}\t{{.Image}}" | grep -E "api|web"
echo ""

# 如果没有指定版本，显示可用版本
if [ -z "$NEW_VERSION" ]; then
    echo -e "${YELLOW}📋 Docker Hub 上最新的 dify-api 版本：${NC}"
    curl -s "https://hub.docker.com/v2/repositories/langgenius/dify-api/tags?page_size=10" 2>/dev/null | \
        python3 -c "import sys,json; tags=json.load(sys.stdin)['results']; print('\n'.join(['   ' + t['name'] for t in tags[:10]]))" 2>/dev/null || \
        echo "   (无法获取版本列表，请手动查看 Docker Hub)"
    
    echo ""
    echo -e "${YELLOW}请指定要升级的版本，例如：${NC}"
    echo "   $0 1.11.0"
    echo ""
    exit 0
fi

echo -e "${GREEN}🎯 目标版本: ${NEW_VERSION}${NC}"
echo ""

# 确认升级
echo -e "${YELLOW}⚠️  升级前请确保已在 Dokploy 中更新 Compose 文件的镜像版本！${NC}"
echo ""
read -p "是否继续？(y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "升级已取消"
    exit 0
fi

# 步骤 1: 备份数据库
echo ""
echo -e "${BLUE}📦 [1/4] 备份数据库...${NC}"
BACKUP_FILE="dify_backup_$(date +%Y%m%d_%H%M%S).sql"
BACKUP_PLUGIN_FILE="dify_plugin_backup_$(date +%Y%m%d_%H%M%S).sql"

docker exec ${STACK_NAME}-db-1 pg_dump -U postgres dify > ${BACKUP_FILE} 2>/dev/null && \
    echo -e "   ${GREEN}✅ dify 数据库已备份: ${BACKUP_FILE}${NC}" || \
    echo -e "   ${YELLOW}⚠️ dify 数据库备份失败${NC}"

docker exec ${STACK_NAME}-db-1 pg_dump -U postgres dify_plugin > ${BACKUP_PLUGIN_FILE} 2>/dev/null && \
    echo -e "   ${GREEN}✅ dify_plugin 数据库已备份: ${BACKUP_PLUGIN_FILE}${NC}" || \
    echo -e "   ${YELLOW}⚠️ dify_plugin 数据库备份失败（可能不存在）${NC}"

# 步骤 2: 拉取新镜像
echo ""
echo -e "${BLUE}⬇️ [2/4] 拉取新镜像...${NC}"
docker pull langgenius/dify-api:${NEW_VERSION}
docker pull langgenius/dify-web:${NEW_VERSION}
echo -e "   ${GREEN}✅ 镜像拉取完成${NC}"

# 步骤 3: 提示用户在 Dokploy 中操作
echo ""
echo -e "${BLUE}🔄 [3/4] 请在 Dokploy 中执行以下操作：${NC}"
echo ""
echo -e "${YELLOW}   1. 打开 Dokploy 管理面板${NC}"
echo -e "${YELLOW}   2. 进入 dify-stack 的 General 选项卡${NC}"
echo -e "${YELLOW}   3. 在 Compose File 中将以下镜像版本更新为 ${NEW_VERSION}：${NC}"
echo "      - langgenius/dify-api"
echo "      - langgenius/dify-web"
echo -e "${YELLOW}   4. 点击 Save 保存${NC}"
echo -e "${YELLOW}   5. 点击 Deploy 重新部署${NC}"
echo ""
read -p "完成 Dokploy 部署后按 Enter 继续..."

# 步骤 4: 运行修复脚本
echo ""
echo -e "${BLUE}🔧 [4/4] 运行修复脚本...${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/fix-dify-deployment.sh" ]; then
    bash "${SCRIPT_DIR}/fix-dify-deployment.sh"
else
    echo -e "${YELLOW}⚠️ 修复脚本不存在，请手动运行 fix-dify-deployment.sh${NC}"
fi

# 完成
echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}   🎉 升级完成！${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "新版本镜像："
docker ps --filter "name=${STACK_NAME}" --format "table {{.Names}}\t{{.Image}}" | grep -E "api|web"
echo ""
echo -e "数据库备份文件："
echo "   - ${BACKUP_FILE}"
echo "   - ${BACKUP_PLUGIN_FILE}"
echo ""
echo -e "${YELLOW}如果升级出现问题，可以回滚：${NC}"
echo "   1. 在 Dokploy 中将镜像版本改回旧版本"
echo "   2. 重新部署"
echo "   3. 恢复数据库: docker exec -i ${STACK_NAME}-db-1 psql -U postgres dify < ${BACKUP_FILE}"


