# Dify 在 Dokploy 上的部署指南

> 作者：傲娇天才少女哈雷酱 (￣▽￣)b
> 日期：2024-12-07
> 版本：1.0

---

## 📋 目录

1. [部署概述](#部署概述)
2. [前置条件](#前置条件)
3. [第一步：创建 Dokploy Compose 服务](#第一步创建-dokploy-compose-服务)
4. [第二步：配置 Docker Compose 文件](#第二步配置-docker-compose-文件)
5. [第三步：配置环境变量](#第三步配置环境变量)
6. [第四步：部署](#第四步部署)
7. [第五步：修复权限问题](#第五步修复权限问题)
8. [第六步：修复 Plugin Daemon](#第六步修复-plugin-daemon)
9. [常见问题与解决方案](#常见问题与解决方案)
10. [配置文件参考](#配置文件参考)

---

## 部署概述

### 架构说明

Dify 在 Dokploy 上的部署架构：

```
                    ┌─────────────────┐
                    │   Traefik       │
                    │   (Dokploy)     │
                    └────────┬────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
     ┌────────▼────────┐          ┌────────▼────────┐
     │   API Service   │          │   Web Service   │
     │   (port 5001)   │          │   (port 3000)   │
     │   /api/*        │          │   其他路径       │
     │   /console/api/*│          │                 │
     │   /v1/*         │          │                 │
     │   /files/*      │          │                 │
     └────────┬────────┘          └─────────────────┘
              │
    ┌─────────┴─────────────────────────────┐
    │                                       │
┌───▼───┐  ┌───────┐  ┌────────┐  ┌────────▼────────┐
│  DB   │  │ Redis │  │Weaviate│  │  Plugin Daemon  │
│ Pg15  │  │   6   │  │ 1.27   │  │     0.4.1       │
└───────┘  └───────┘  └────────┘  └─────────────────┘
```

### 关键点

1. **不使用 Nginx**：Dokploy 的 Traefik 直接路由到 API 和 Web 服务
2. **不使用 Sandbox/SSRF Proxy**：这些服务需要本地配置文件，在 Raw 模式下不可用
3. **手动配置 Plugin Daemon**：需要正确设置网络别名和环境变量

---

## 前置条件

1. ✅ Dokploy 已安装并运行
2. ✅ 域名已配置 DNS 指向服务器 IP
3. ✅ Traefik 已配置 Let's Encrypt 证书解析器 (名称: `letsencrypt`)
4. ✅ `dokploy-network` 网络已存在

### 验证 Dokploy 环境

```bash
# 检查 dokploy-network
docker network ls | grep dokploy

# 检查 Traefik 配置
docker exec dokploy-traefik cat /etc/traefik/traefik.yml | grep -A 5 "certificatesResolvers"
```

---

## 第一步：创建 Dokploy Compose 服务

1. 登录 Dokploy 管理面板
2. 进入 **Projects** → 创建或选择项目
3. 点击 **+ Create Service** → 选择 **Compose**
4. 填写信息：
   - **Name**: `dify-stack`
   - **Description**: `Dify LLM Application Platform`
5. 选择 **Raw** 模式（Provider 选项卡）

---

## 第二步：配置 Docker Compose 文件

在 **General** → **Compose File** 中粘贴以下内容：

```yaml
# ==================================================================
# Dokploy 部署专用 Docker Compose 文件 - V2 简化版
# 直接使用 Traefik 路由到 api 和 web，绕过 nginx
# ==================================================================

x-shared-env: &shared-api-worker-env
  CONSOLE_API_URL: ${CONSOLE_API_URL:-}
  CONSOLE_WEB_URL: ${CONSOLE_WEB_URL:-}
  SERVICE_API_URL: ${SERVICE_API_URL:-}
  TRIGGER_URL: ${TRIGGER_URL:-http://localhost}
  APP_API_URL: ${APP_API_URL:-}
  APP_WEB_URL: ${APP_WEB_URL:-}
  FILES_URL: ${FILES_URL:-}
  INTERNAL_FILES_URL: ${INTERNAL_FILES_URL:-}
  LANG: ${LANG:-en_US.UTF-8}
  LC_ALL: ${LC_ALL:-en_US.UTF-8}
  PYTHONIOENCODING: ${PYTHONIOENCODING:-utf-8}
  LOG_LEVEL: ${LOG_LEVEL:-INFO}
  LOG_FILE: ${LOG_FILE:-}
  LOG_FILE_MAX_SIZE: ${LOG_FILE_MAX_SIZE:-20}
  LOG_FILE_BACKUP_COUNT: ${LOG_FILE_BACKUP_COUNT:-5}
  LOG_DATEFORMAT: ${LOG_DATEFORMAT:-%Y-%m-%d %H:%M:%S}
  LOG_TZ: ${LOG_TZ:-UTC}
  DEBUG: ${DEBUG:-false}
  FLASK_DEBUG: ${FLASK_DEBUG:-false}
  SECRET_KEY: ${SECRET_KEY:-sk-9f73s3ljTXVcMT3Blb3ljTqtsKiGHXVcMT3BlbkFJLK7U}
  DEPLOY_ENV: ${DEPLOY_ENV:-PRODUCTION}
  OPENAI_API_BASE: ${OPENAI_API_BASE:-https://api.openai.com/v1}
  MIGRATION_ENABLED: ${MIGRATION_ENABLED:-true}
  DB_USERNAME: ${DB_USERNAME:-postgres}
  DB_PASSWORD: ${DB_PASSWORD:-difyai123456}
  DB_HOST: ${DB_HOST:-db}
  DB_PORT: ${DB_PORT:-5432}
  DB_DATABASE: ${DB_DATABASE:-dify}
  REDIS_HOST: ${REDIS_HOST:-redis}
  REDIS_PORT: ${REDIS_PORT:-6379}
  REDIS_PASSWORD: ${REDIS_PASSWORD:-difyai123456}
  REDIS_USE_SSL: ${REDIS_USE_SSL:-false}
  REDIS_DB: 0
  CELERY_BROKER_URL: ${CELERY_BROKER_URL:-redis://:difyai123456@redis:6379/1}
  WEB_API_CORS_ALLOW_ORIGINS: ${WEB_API_CORS_ALLOW_ORIGINS:-*}
  CONSOLE_CORS_ALLOW_ORIGINS: ${CONSOLE_CORS_ALLOW_ORIGINS:-*}
  STORAGE_TYPE: ${STORAGE_TYPE:-opendal}
  OPENDAL_SCHEME: ${OPENDAL_SCHEME:-fs}
  OPENDAL_FS_ROOT: ${OPENDAL_FS_ROOT:-/app/api/storage}
  VECTOR_STORE: ${VECTOR_STORE:-weaviate}
  WEAVIATE_ENDPOINT: ${WEAVIATE_ENDPOINT:-http://weaviate:8080}
  WEAVIATE_API_KEY: ${WEAVIATE_API_KEY:-WVF5YThaHlkYwhGUSmCRgsX3tD5ngdN8pkih}
  CODE_EXECUTION_ENDPOINT: ${CODE_EXECUTION_ENDPOINT:-http://sandbox:8194}
  CODE_EXECUTION_API_KEY: ${CODE_EXECUTION_API_KEY:-dify-sandbox}
  PLUGIN_DAEMON_BASE_URL: ${PLUGIN_DAEMON_BASE_URL:-http://plugin_daemon:5002}
  PLUGIN_DAEMON_KEY: ${PLUGIN_DAEMON_KEY:-lYkiYYT6owG+71oLerGzA7GXCgOT++6ovaezWAjpCjf+Sjc3ZtU+qUEi}
  PLUGIN_DAEMON_URL: ${PLUGIN_DAEMON_URL:-http://plugin_daemon:5002}
  INNER_API_KEY_FOR_PLUGIN: ${INNER_API_KEY_FOR_PLUGIN:-QaHbTe77CtuXmsfyhR7+vRjI/+XbV1AaFy691iy+kGDv2Jvy0/eAh8Y1}
  ENDPOINT_URL_TEMPLATE: ${ENDPOINT_URL_TEMPLATE:-http://api:5001/e/{hook_id}}
  MARKETPLACE_API_URL: ${MARKETPLACE_API_URL:-https://marketplace.dify.ai}
  MARKETPLACE_ENABLED: ${MARKETPLACE_ENABLED:-true}

services:
  # ============================================
  # API 服务 - 带 Traefik 标签
  # ============================================
  api:
    image: langgenius/dify-api:1.10.1-fix.1
    restart: always
    environment:
      <<: *shared-api-worker-env
      MODE: api
    depends_on:
      - db
      - redis
    volumes:
      - api_storage:/app/api/storage
    networks:
      - default
      - dokploy-network
    labels:
      # ⚠️ 修改下面的域名为你的域名
      - "traefik.enable=true"
      # ⚠️ 包含 /mcp 路径用于 MCP 服务器支持
      - "traefik.http.routers.dify-api-http.rule=Host(`dify.mymanus.me`) && (PathPrefix(`/api`) || PathPrefix(`/console/api`) || PathPrefix(`/v1`) || PathPrefix(`/files`) || PathPrefix(`/mcp`))"
      - "traefik.http.routers.dify-api-http.entrypoints=web"
      - "traefik.http.routers.dify-api-http.middlewares=redirect-to-https"
      - "traefik.http.routers.dify-api.rule=Host(`dify.mymanus.me`) && (PathPrefix(`/api`) || PathPrefix(`/console/api`) || PathPrefix(`/v1`) || PathPrefix(`/files`) || PathPrefix(`/mcp`))"
      - "traefik.http.routers.dify-api.entrypoints=websecure"
      - "traefik.http.routers.dify-api.tls=true"
      - "traefik.http.routers.dify-api.tls.certresolver=letsencrypt"
      - "traefik.http.routers.dify-api.priority=100"
      - "traefik.http.services.dify-api.loadbalancer.server.port=5001"
      - "traefik.http.middlewares.redirect-to-https.redirectscheme.scheme=https"
      - "traefik.http.middlewares.redirect-to-https.redirectscheme.permanent=true"

  # ============================================
  # Worker 服务
  # ============================================
  worker:
    image: langgenius/dify-api:1.10.1-fix.1
    restart: always
    environment:
      <<: *shared-api-worker-env
      MODE: worker
    depends_on:
      - db
      - redis
    volumes:
      - api_storage:/app/api/storage
    networks:
      - default
      - dokploy-network

  # ============================================
  # Worker Beat 服务
  # ============================================
  worker_beat:
    image: langgenius/dify-api:1.10.1-fix.1
    restart: always
    environment:
      <<: *shared-api-worker-env
      MODE: worker
      CELERY_AUTO_SCALE: "false"
    depends_on:
      - db
      - redis
    volumes:
      - api_storage:/app/api/storage
    entrypoint:
      [
        "celery",
        "-A",
        "app.celery",
        "beat",
        "-l",
        "INFO"
      ]
    networks:
      - default
      - dokploy-network

  # ============================================
  # Web 前端服务 - 带 Traefik 标签
  # ============================================
  web:
    image: langgenius/dify-web:1.10.1-fix.1
    restart: always
    environment:
      CONSOLE_API_URL: ${CONSOLE_API_URL:-}
      APP_API_URL: ${APP_API_URL:-}
      NEXT_TELEMETRY_DISABLED: ${NEXT_TELEMETRY_DISABLED:-1}
    networks:
      - default
      - dokploy-network
    labels:
      # ⚠️ 修改下面的域名为你的域名
      - "traefik.enable=true"
      - "traefik.http.routers.dify-web-http.rule=Host(`dify.mymanus.me`)"
      - "traefik.http.routers.dify-web-http.entrypoints=web"
      - "traefik.http.routers.dify-web-http.middlewares=redirect-to-https"
      - "traefik.http.routers.dify-web.rule=Host(`dify.mymanus.me`)"
      - "traefik.http.routers.dify-web.entrypoints=websecure"
      - "traefik.http.routers.dify-web.tls=true"
      - "traefik.http.routers.dify-web.tls.certresolver=letsencrypt"
      - "traefik.http.routers.dify-web.priority=1"
      - "traefik.http.services.dify-web.loadbalancer.server.port=3000"

  # ============================================
  # 数据库服务
  # ============================================
  db:
    image: postgres:15-alpine
    restart: always
    environment:
      POSTGRES_USER: ${DB_USERNAME:-postgres}
      POSTGRES_PASSWORD: ${DB_PASSWORD:-difyai123456}
      POSTGRES_DB: ${DB_DATABASE:-dify}
    command: >
      postgres -c 'max_connections=400'
    volumes:
      - db_data:/var/lib/postgresql/data
    healthcheck:
      test: [ "CMD", "pg_isready" ]
      interval: 1s
      timeout: 3s
      retries: 30
    networks:
      - default
      - dokploy-network

  # ============================================
  # Redis 服务
  # ============================================
  redis:
    image: redis:6-alpine
    restart: always
    command: redis-server --requirepass ${REDIS_PASSWORD:-difyai123456}
    volumes:
      - redis_data:/data
    healthcheck:
      test: [ "CMD", "redis-cli", "ping" ]
    networks:
      - default
      - dokploy-network

  # ============================================
  # Weaviate 向量数据库
  # ============================================
  weaviate:
    image: semitechnologies/weaviate:1.27.0
    restart: always
    volumes:
      - weaviate_data:/var/lib/weaviate
    environment:
      AUTHENTICATION_APIKEY_ENABLED: true
      AUTHENTICATION_APIKEY_ALLOWED_KEYS: ${WEAVIATE_API_KEY:-WVF5YThaHlkYwhGUSmCRgsX3tD5ngdN8pkih}
      AUTHENTICATION_APIKEY_USERS: hello@dify.ai
      AUTHORIZATION_ADMINLIST_ENABLED: true
      AUTHORIZATION_ADMINLIST_USERS: hello@dify.ai
      QUERY_DEFAULTS_LIMIT: 25
      DEFAULT_VECTORIZER_MODULE: none
      CLUSTER_HOSTNAME: node1
      PERSISTENCE_DATA_PATH: /var/lib/weaviate
    networks:
      - default
      - dokploy-network

  # ============================================
  # Plugin Daemon 服务（关键！）
  # ============================================
  plugin_daemon:
    image: langgenius/dify-plugin-daemon:0.4.1-local
    restart: always
    environment:
      # 数据库配置
      DB_HOST: db
      DB_PORT: 5432
      DB_USERNAME: postgres
      DB_PASSWORD: difyai123456
      DB_DATABASE: dify_plugin
      # Redis 配置
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: difyai123456
      REDIS_DB: 0
      # 服务配置
      SERVER_PORT: 5002
      SERVER_KEY: ${PLUGIN_DAEMON_KEY:-lYkiYYT6owG+71oLerGzA7GXCgOT++6ovaezWAjpCjf+Sjc3ZtU+qUEi}
      MAX_PLUGIN_PACKAGE_SIZE: 52428800
      PPROF_ENABLED: false
      DIFY_INNER_API_URL: http://api:5001
      DIFY_INNER_API_KEY: ${INNER_API_KEY_FOR_PLUGIN:-QaHbTe77CtuXmsfyhR7+vRjI/+XbV1AaFy691iy+kGDv2Jvy0/eAh8Y1}
      # 插件远程安装配置
      PLUGIN_REMOTE_INSTALLING_HOST: 0.0.0.0
      PLUGIN_REMOTE_INSTALLING_PORT: 5003
      # 插件运行时配置（关键！）
      PLUGIN_WORKING_PATH: /app/storage/cwd
      PLUGIN_STORAGE_TYPE: local
      PLUGIN_STORAGE_LOCAL_ROOT: /app/storage
      PLUGIN_INSTALLED_PATH: plugin
      PLUGIN_PACKAGE_CACHE_PATH: plugin_packages
      PLUGIN_MEDIA_CACHE_PATH: assets
      # 插件执行配置
      PLUGIN_MAX_EXECUTION_TIMEOUT: 600
      PLUGIN_STDIO_BUFFER_SIZE: 1024
      PLUGIN_STDIO_MAX_BUFFER_SIZE: 5242880
      PYTHON_ENV_INIT_TIMEOUT: 120
      FORCE_VERIFYING_SIGNATURE: false
      PIP_MIRROR_URL: ""
      ENDPOINT_URL_TEMPLATE: http://api:5001/e/{hook_id}
      PLATFORM: local
    volumes:
      - plugin_daemon_storage:/app/storage
    depends_on:
      - db
      - redis
    networks:
      - default
      - dokploy-network

volumes:
  api_storage:
  db_data:
  redis_data:
  weaviate_data:
  plugin_daemon_storage:

networks:
  default:
  dokploy-network:
    external: true
```

> ⚠️ **重要**：将所有 `dify.mymanus.me` 替换为你的实际域名！

点击 **Save** 保存。

---

## 第三步：配置环境变量

切换到 **Environment** 选项卡，粘贴以下内容：

```bash
# ⚠️ 将 dify.mymanus.me 替换为你的域名
CONSOLE_API_URL=https://dify.mymanus.me
CONSOLE_WEB_URL=https://dify.mymanus.me
SERVICE_API_URL=https://dify.mymanus.me
APP_API_URL=https://dify.mymanus.me
APP_WEB_URL=https://dify.mymanus.me
FILES_URL=https://dify.mymanus.me
TRIGGER_URL=https://dify.mymanus.me

# 内部通信 URL
INTERNAL_FILES_URL=http://api:5001

# 安全密钥 - 请生成新的随机字符串
SECRET_KEY=your-random-secret-key-here

# 数据库配置
DB_USERNAME=postgres
DB_PASSWORD=difyai123456
DB_HOST=db
DB_PORT=5432
DB_DATABASE=dify

# Redis 配置
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=difyai123456
REDIS_DB=0
CELERY_BROKER_URL=redis://:difyai123456@redis:6379/1

# 存储配置
STORAGE_TYPE=opendal
OPENDAL_SCHEME=fs
OPENDAL_FS_ROOT=storage

# 向量数据库配置
VECTOR_STORE=weaviate
WEAVIATE_ENDPOINT=http://weaviate:8080
WEAVIATE_API_KEY=WVF5YThaHlkYwhGUSmCRgsX3tD5ngdN8pkih

# Plugin 配置
PLUGIN_DAEMON_PORT=5002
PLUGIN_DAEMON_KEY=lYkiYYT6owG+71oLerGzA7GXCgOT++6ovaezWAjpCjf+Sjc3ZtU+qUEi
PLUGIN_DAEMON_URL=http://plugin_daemon:5002
PLUGIN_DIFY_INNER_API_KEY=QaHbTe77CtuXmsfyhR7+vRjI/+XbV1AaFy691iy+kGDv2Jvy0/eAh8Y1
PLUGIN_DIFY_INNER_API_URL=http://api:5001
MARKETPLACE_ENABLED=true
MARKETPLACE_API_URL=https://marketplace.dify.ai

# 日志配置 - 禁用文件日志避免权限问题
LOG_FILE=
LOG_LEVEL=INFO
DEBUG=false
FLASK_DEBUG=false
DEPLOY_ENV=PRODUCTION
```

点击 **Save** 保存。

---

## 第四步：部署

1. 切换到 **General** 选项卡
2. 点击 **Deploy** 按钮
3. 确认部署
4. 等待镜像拉取和容器启动（首次约 5-10 分钟）

---

## 第五步：修复权限问题

部署完成后，需要在服务器上执行以下命令修复存储权限：

```bash
# 获取 compose 项目名称（例如：stack-nqg0lt）
STACK_NAME=$(docker ps --filter "name=api" --format "{{.Names}}" | grep -oP "stack-[a-z0-9]+")
echo "Stack Name: $STACK_NAME"

# 修复 api_storage 权限
API_STORAGE=$(docker volume inspect ${STACK_NAME}_api_storage 2>/dev/null | grep Mountpoint | awk -F'"' '{print $4}')
sudo chmod -R 777 "$API_STORAGE"
sudo chown -R 1000:1000 "$API_STORAGE"

# 修复 plugin_daemon_storage 权限
PLUGIN_STORAGE=$(docker volume inspect ${STACK_NAME}_plugin_daemon_storage 2>/dev/null | grep Mountpoint | awk -F'"' '{print $4}')
sudo chmod -R 777 "$PLUGIN_STORAGE"
sudo chown -R 1000:1000 "$PLUGIN_STORAGE"

# 重启 API 和 Worker
docker restart ${STACK_NAME}-api-1 ${STACK_NAME}-worker-1
```

---

## 第六步：修复 Plugin Daemon

**这是最关键的一步！** Dokploy 部署的 Plugin Daemon 可能缺少必要配置。

### 6.1 创建 Plugin 数据库

```bash
STACK_NAME=$(docker ps --filter "name=db" --format "{{.Names}}" | grep -oP "stack-[a-z0-9]+")
docker exec ${STACK_NAME}-db-1 psql -U postgres -c "CREATE DATABASE dify_plugin;"
```

### 6.2 删除原有 Plugin Daemon 容器

```bash
docker rm -f ${STACK_NAME}-plugin_daemon-1 2>/dev/null || true
```

### 6.3 手动创建 Plugin Daemon 容器

```bash
STACK_NAME=$(docker ps --filter "name=api" --format "{{.Names}}" | grep -oP "stack-[a-z0-9]+")

docker run -d \
  --name ${STACK_NAME}-plugin_daemon-1 \
  --network ${STACK_NAME}_default \
  --network-alias plugin_daemon \
  --restart always \
  -e DB_HOST=db \
  -e DB_PORT=5432 \
  -e DB_USERNAME=postgres \
  -e DB_PASSWORD=difyai123456 \
  -e DB_DATABASE=dify_plugin \
  -e REDIS_HOST=redis \
  -e REDIS_PORT=6379 \
  -e REDIS_PASSWORD=difyai123456 \
  -e REDIS_DB=0 \
  -e SERVER_PORT=5002 \
  -e "SERVER_KEY=lYkiYYT6owG+71oLerGzA7GXCgOT++6ovaezWAjpCjf+Sjc3ZtU+qUEi" \
  -e MAX_PLUGIN_PACKAGE_SIZE=52428800 \
  -e PPROF_ENABLED=false \
  -e DIFY_INNER_API_URL=http://api:5001 \
  -e "DIFY_INNER_API_KEY=QaHbTe77CtuXmsfyhR7+vRjI/+XbV1AaFy691iy+kGDv2Jvy0/eAh8Y1" \
  -e PLUGIN_REMOTE_INSTALLING_HOST=0.0.0.0 \
  -e PLUGIN_REMOTE_INSTALLING_PORT=5003 \
  -e PLUGIN_WORKING_PATH=/app/storage/cwd \
  -e PLUGIN_STORAGE_TYPE=local \
  -e PLUGIN_STORAGE_LOCAL_ROOT=/app/storage \
  -e PLUGIN_INSTALLED_PATH=plugin \
  -e PLUGIN_PACKAGE_CACHE_PATH=plugin_packages \
  -e PLUGIN_MEDIA_CACHE_PATH=assets \
  -e PLUGIN_MAX_EXECUTION_TIMEOUT=600 \
  -e PLUGIN_STDIO_BUFFER_SIZE=1024 \
  -e PLUGIN_STDIO_MAX_BUFFER_SIZE=5242880 \
  -e PYTHON_ENV_INIT_TIMEOUT=120 \
  -e FORCE_VERIFYING_SIGNATURE=false \
  -e "ENDPOINT_URL_TEMPLATE=http://api:5001/e/{hook_id}" \
  -e PLATFORM=local \
  -v ${STACK_NAME}_plugin_daemon_storage:/app/storage \
  langgenius/dify-plugin-daemon:0.4.1-local
```

> ⚠️ **关键点**：
> 1. `--network-alias plugin_daemon` 必须设置，否则 API 无法通过 `plugin_daemon` 主机名找到它！
> 2. `PLUGIN_STORAGE_TYPE`、`PLUGIN_INSTALLED_PATH` 等运行时配置必须设置，否则插件无法正常加载！

### 6.4 验证 Plugin Daemon

```bash
# 检查容器状态
docker ps --filter "name=plugin_daemon"

# 检查日志
docker logs ${STACK_NAME}-plugin_daemon-1 --tail 20

# 应该看到：
# [INFO] dify plugin db initialized
# [INFO] start plugin manager daemon...
# [INFO] Persistence initialized
# [INFO] current node has become the master of the cluster
```

### 6.5 重启 API 服务

```bash
docker restart ${STACK_NAME}-api-1
```

---

## 常见问题与解决方案

### Q1: "PermissionError: Permission denied: '/app/logs/server.log'"

**原因**：日志文件写入权限问题

**解决**：在环境变量中设置 `LOG_FILE=` （留空）

### Q2: "Setup failed: PermissionDenied at write => permission denied"

**原因**：存储目录权限问题

**解决**：执行第五步的权限修复命令

### Q3: "Failed to request plugin daemon"

**原因**：Plugin Daemon 容器网络别名未设置

**解决**：
1. 删除现有 plugin_daemon 容器
2. 使用第六步中的命令重新创建（注意 `--network-alias plugin_daemon`）

### Q4: "PLUGIN_REMOTE_INSTALLING_PORT: invalid syntax"

**原因**：环境变量值为空

**解决**：手动创建 Plugin Daemon 容器时明确设置 `PLUGIN_REMOTE_INSTALLING_PORT=5003`

### Q5: "database dify_plugin does not exist"

**原因**：Plugin 数据库未创建

**解决**：
```bash
docker exec ${STACK_NAME}-db-1 psql -U postgres -c "CREATE DATABASE dify_plugin;"
```

### Q6: "init redis client failed"

**原因**：Plugin Daemon 缺少 Redis 配置

**解决**：在创建容器时添加 Redis 环境变量：
- `REDIS_HOST=redis`
- `REDIS_PORT=6379`
- `REDIS_PASSWORD=difyai123456`

---

## 配置文件参考

所有配置文件保存在服务器 `/opt/dify/docker/` 目录下：

- `dokploy-compose-v2.yaml` - Docker Compose 配置
- `env.dokploy` - 环境变量配置
- `DOKPLOY_DEPLOYMENT_GUIDE.md` - 本指南

---

## 部署后检查清单

- [ ] 访问 https://your-domain.com 显示 Dify 安装页面
- [ ] 能够成功创建管理员账户
- [ ] 能够创建应用
- [ ] 没有 "Failed to request plugin daemon" 错误
- [ ] 所有容器状态为 "Up" 且无 Restarting

### 检查容器状态

```bash
docker ps --filter "name=stack-" --format "table {{.Names}}\t{{.Status}}"
```

应该看到类似：
```
NAMES                          STATUS
stack-xxx-plugin_daemon-1      Up X minutes
stack-xxx-worker_beat-1        Up X minutes
stack-xxx-api-1                Up X minutes
stack-xxx-worker-1             Up X minutes
stack-xxx-db-1                 Up X minutes (healthy)
stack-xxx-web-1                Up X minutes
stack-xxx-redis-1              Up X minutes (healthy)
stack-xxx-weaviate-1           Up X minutes
```

---

## 一键部署脚本

保存以下脚本为 `fix-dify-deployment.sh`：

```bash
#!/bin/bash
# Dify Dokploy 部署修复脚本
# 在 Dokploy 部署完成后运行此脚本

set -e

echo "🚀 开始修复 Dify 部署..."

# 获取 stack 名称
STACK_NAME=$(docker ps --filter "name=api" --format "{{.Names}}" | grep -oP "stack-[a-z0-9]+" | head -1)

if [ -z "$STACK_NAME" ]; then
    echo "❌ 未找到 Dify 容器，请先在 Dokploy 中部署"
    exit 1
fi

echo "📦 Stack 名称: $STACK_NAME"

# 1. 修复存储权限
echo "🔧 修复存储权限..."
API_STORAGE=$(docker volume inspect ${STACK_NAME}_api_storage 2>/dev/null | grep Mountpoint | awk -F'"' '{print $4}')
PLUGIN_STORAGE=$(docker volume inspect ${STACK_NAME}_plugin_daemon_storage 2>/dev/null | grep Mountpoint | awk -F'"' '{print $4}')

[ -n "$API_STORAGE" ] && sudo chmod -R 777 "$API_STORAGE" && sudo chown -R 1000:1000 "$API_STORAGE"
[ -n "$PLUGIN_STORAGE" ] && sudo chmod -R 777 "$PLUGIN_STORAGE" && sudo chown -R 1000:1000 "$PLUGIN_STORAGE"

# 2. 创建 plugin 数据库
echo "🗄️ 创建 Plugin 数据库..."
docker exec ${STACK_NAME}-db-1 psql -U postgres -c "CREATE DATABASE dify_plugin;" 2>/dev/null || echo "数据库已存在"

# 3. 重建 Plugin Daemon（包含完整的运行时配置）
echo "🔄 重建 Plugin Daemon..."
docker rm -f ${STACK_NAME}-plugin_daemon-1 2>/dev/null || true

docker run -d \
  --name ${STACK_NAME}-plugin_daemon-1 \
  --network ${STACK_NAME}_default \
  --network-alias plugin_daemon \
  --restart always \
  -e DB_HOST=db \
  -e DB_PORT=5432 \
  -e DB_USERNAME=postgres \
  -e DB_PASSWORD=difyai123456 \
  -e DB_DATABASE=dify_plugin \
  -e REDIS_HOST=redis \
  -e REDIS_PORT=6379 \
  -e REDIS_PASSWORD=difyai123456 \
  -e REDIS_DB=0 \
  -e SERVER_PORT=5002 \
  -e "SERVER_KEY=lYkiYYT6owG+71oLerGzA7GXCgOT++6ovaezWAjpCjf+Sjc3ZtU+qUEi" \
  -e MAX_PLUGIN_PACKAGE_SIZE=52428800 \
  -e PPROF_ENABLED=false \
  -e DIFY_INNER_API_URL=http://api:5001 \
  -e "DIFY_INNER_API_KEY=QaHbTe77CtuXmsfyhR7+vRjI/+XbV1AaFy691iy+kGDv2Jvy0/eAh8Y1" \
  -e PLUGIN_REMOTE_INSTALLING_HOST=0.0.0.0 \
  -e PLUGIN_REMOTE_INSTALLING_PORT=5003 \
  -e PLUGIN_WORKING_PATH=/app/storage/cwd \
  -e PLUGIN_STORAGE_TYPE=local \
  -e PLUGIN_STORAGE_LOCAL_ROOT=/app/storage \
  -e PLUGIN_INSTALLED_PATH=plugin \
  -e PLUGIN_PACKAGE_CACHE_PATH=plugin_packages \
  -e PLUGIN_MEDIA_CACHE_PATH=assets \
  -e PLUGIN_MAX_EXECUTION_TIMEOUT=600 \
  -e PLUGIN_STDIO_BUFFER_SIZE=1024 \
  -e PLUGIN_STDIO_MAX_BUFFER_SIZE=5242880 \
  -e PYTHON_ENV_INIT_TIMEOUT=120 \
  -e FORCE_VERIFYING_SIGNATURE=false \
  -e "ENDPOINT_URL_TEMPLATE=http://api:5001/e/{hook_id}" \
  -e PLATFORM=local \
  -v ${STACK_NAME}_plugin_daemon_storage:/app/storage \
  langgenius/dify-plugin-daemon:0.4.1-local

# 4. 重启 API
echo "🔄 重启 API 服务..."
sleep 5
docker restart ${STACK_NAME}-api-1

# 5. 检查状态
echo ""
echo "✅ 修复完成！检查容器状态："
sleep 3
docker ps --filter "name=${STACK_NAME}" --format "table {{.Names}}\t{{.Status}}"

echo ""
echo "🎉 完成！请访问你的 Dify 域名测试"
```

使用方法：
```bash
chmod +x fix-dify-deployment.sh
sudo ./fix-dify-deployment.sh
```

---

**祝部署顺利！** 

*— 天才少女哈雷酱 (￣▽￣)b*


---

## 升级指南

### 升级步骤

当 Dify 发布新版本时，按以下步骤升级：

#### 步骤 1：查看最新版本

访问 [Dify GitHub Releases](https://github.com/langgenius/dify/releases) 查看最新版本号。

或使用命令查看 Docker Hub 上的标签：
```bash
# 查看 dify-api 最新标签
curl -s "https://hub.docker.com/v2/repositories/langgenius/dify-api/tags?page_size=10" | python3 -c "import sys,json; tags=json.load(sys.stdin)['results']; print('\n'.join([t['name'] for t in tags]))"

# 查看 dify-web 最新标签
curl -s "https://hub.docker.com/v2/repositories/langgenius/dify-web/tags?page_size=10" | python3 -c "import sys,json; tags=json.load(sys.stdin)['results']; print('\n'.join([t['name'] for t in tags]))"
```

#### 步骤 2：备份数据（重要！）

```bash
# 获取 stack 名称
STACK_NAME=$(docker ps --filter "name=api" --format "{{.Names}}" | grep -oP "stack-[a-z0-9]+" | head -1)

# 备份数据库
docker exec ${STACK_NAME}-db-1 pg_dump -U postgres dify > dify_backup_$(date +%Y%m%d).sql
docker exec ${STACK_NAME}-db-1 pg_dump -U postgres dify_plugin > dify_plugin_backup_$(date +%Y%m%d).sql

echo "✅ 数据库备份完成"
```

#### 步骤 3：更新 Docker Compose 文件

在 Dokploy 的 **General** → **Compose File** 中，修改镜像版本：

```yaml
# 将旧版本
image: langgenius/dify-api:1.10.1-fix.1
image: langgenius/dify-web:1.10.1-fix.1

# 改为新版本（例如 1.11.0）
image: langgenius/dify-api:1.11.0
image: langgenius/dify-web:1.11.0
```

需要修改的位置（共 4 处）：
- `api` 服务
- `worker` 服务
- `worker_beat` 服务
- `web` 服务

点击 **Save** 保存。

#### 步骤 4：检查 Plugin Daemon 版本

访问 [dify-plugin-daemon releases](https://github.com/langgenius/dify-plugin-daemon/releases) 查看是否有新版本。

如果需要升级 plugin-daemon：
```bash
STACK_NAME=$(docker ps --filter "name=api" --format "{{.Names}}" | grep -oP "stack-[a-z0-9]+" | head -1)

# 拉取新镜像
docker pull langgenius/dify-plugin-daemon:NEW_VERSION

# 删除旧容器
docker rm -f ${STACK_NAME}-plugin_daemon-1

# 使用 fix 脚本重建（修改脚本中的版本号）
# 或手动创建新容器
```

#### 步骤 5：重新部署

1. 在 Dokploy 中点击 **Deploy** 按钮
2. 等待新镜像拉取完成
3. 容器自动重启

#### 步骤 6：重新运行修复脚本

```bash
sudo /opt/dify/docker/fix-dify-deployment.sh
```

#### 步骤 7：验证升级

```bash
# 检查版本（通过 API）
curl -s https://your-domain.com/console/api/version

# 检查容器镜像版本
docker ps --filter "name=stack-" --format "table {{.Names}}\t{{.Image}}"
```

---

### 升级注意事项

1. **备份优先**：升级前务必备份数据库
2. **查看更新日志**：阅读 Release Notes 了解破坏性变更
3. **测试环境**：建议先在测试环境验证
4. **回滚准备**：保留旧版本号，以便快速回滚

### 回滚步骤

如果升级失败，回滚到旧版本：

```bash
# 1. 在 Dokploy 中将镜像版本改回旧版本
# 2. 重新部署
# 3. 如需恢复数据库：
docker exec -i ${STACK_NAME}-db-1 psql -U postgres dify < dify_backup_YYYYMMDD.sql
```

---

### 自动升级脚本

保存为 `upgrade-dify.sh`：

```bash
#!/bin/bash
# Dify 升级脚本

NEW_API_VERSION=${1:-"latest"}
NEW_WEB_VERSION=${2:-$NEW_API_VERSION}

STACK_NAME=$(docker ps --filter "name=api" --format "{{.Names}}" | grep -oP "stack-[a-z0-9]+" | head -1)

if [ -z "$STACK_NAME" ]; then
    echo "❌ 未找到 Dify 部署"
    exit 1
fi

echo "🔄 升级 Dify 到版本: API=$NEW_API_VERSION, Web=$NEW_WEB_VERSION"

# 备份
echo "📦 备份数据库..."
docker exec ${STACK_NAME}-db-1 pg_dump -U postgres dify > dify_backup_$(date +%Y%m%d_%H%M%S).sql

# 拉取新镜像
echo "⬇️ 拉取新镜像..."
docker pull langgenius/dify-api:${NEW_API_VERSION}
docker pull langgenius/dify-web:${NEW_WEB_VERSION}

echo ""
echo "✅ 镜像已拉取。请在 Dokploy 中："
echo "   1. 更新 Compose 文件中的镜像版本"
echo "   2. 点击 Deploy 重新部署"
echo "   3. 运行 fix-dify-deployment.sh"
```

使用方法：
```bash
chmod +x upgrade-dify.sh
./upgrade-dify.sh 1.11.0  # 指定版本
```

