#!/bin/bash

# Dify 开发环境一键搭建脚本
# 适用于 Linux 系统

set -e

echo "🚀 开始搭建 Dify 开发环境..."

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查系统要求
check_requirements() {
    echo -e "${YELLOW}检查系统要求...${NC}"
    
    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ Docker 未安装，请先安装 Docker${NC}"
        exit 1
    fi
    
    # 检查 Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        echo -e "${RED}❌ Docker Compose 未安装，请先安装 Docker Compose${NC}"
        exit 1
    fi
    
    # 检查 Python 3.11+
    if ! python3.11 --version &> /dev/null; then
        echo -e "${RED}❌ Python 3.11+ 未安装，请先安装 Python 3.11${NC}"
        exit 1
    fi
    
    # 检查 Node.js
    if ! node --version &> /dev/null; then
        echo -e "${RED}❌ Node.js 未安装，请先安装 Node.js 22.11+${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ 系统要求检查通过${NC}"
}

# 创建项目目录结构
setup_directories() {
    echo -e "${YELLOW}创建项目目录结构...${NC}"
    
    mkdir -p dify-dev/{data,logs,config,scripts}
    mkdir -p dify-dev/data/{postgres,redis,weaviate,storage,uploads}
    mkdir -p dify-dev/logs/{api,worker,web}
    mkdir -p dify-dev/config/{middleware,api,web}
    
    echo -e "${GREEN}✅ 目录结构创建完成${NC}"
}

# 克隆源码
clone_source() {
    echo -e "${YELLOW}克隆 Dify 源码...${NC}"
    
    if [ ! -d "dify-dev/source" ]; then
        git clone https://github.com/langgenius/dify.git dify-dev/source
    else
        echo "源码已存在，跳过克隆"
    fi
    
    echo -e "${GREEN}✅ 源码克隆完成${NC}"
}

# 配置中间件服务
setup_middleware() {
    echo -e "${YELLOW}配置中间件服务...${NC}"
    
    cd dify-dev/source/docker
    
    # 复制中间件环境配置
    cp middleware.env.example ../../../config/middleware/middleware.env
    
    # 创建中间件 docker-compose 文件
    cat > ../../../config/middleware/docker-compose.middleware.yml << 'EOF'
version: '3.8'

services:
  # PostgreSQL 数据库
  postgres:
    image: postgres:15-alpine
    container_name: dify-dev-postgres
    restart: always
    environment:
      POSTGRES_DB: dify
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: difyai123456
      PGDATA: /var/lib/postgresql/data/pgdata
    ports:
      - "5432:5432"
    volumes:
      - ../../../data/postgres:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

  # Redis 缓存
  redis:
    image: redis:6-alpine
    container_name: dify-dev-redis
    restart: always
    command: redis-server --requirepass difyai123456
    ports:
      - "6379:6379"
    volumes:
      - ../../../data/redis:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

  # Weaviate 向量数据库
  weaviate:
    image: semitechnologies/weaviate:1.19.0
    container_name: dify-dev-weaviate
    restart: always
    ports:
      - "8080:8080"
    volumes:
      - ../../../data/weaviate:/var/lib/weaviate
    environment:
      PERSISTENCE_DATA_PATH: /var/lib/weaviate
      QUERY_DEFAULTS_LIMIT: 25
      AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED: true
      DEFAULT_VECTORIZER_MODULE: none
      CLUSTER_HOSTNAME: node1

  # 沙箱服务
  sandbox:
    image: langgenius/dify-sandbox:0.2.12
    container_name: dify-dev-sandbox
    restart: always
    ports:
      - "8194:8194"
    environment:
      API_KEY: dify-sandbox
      GIN_MODE: release
      WORKER_TIMEOUT: 15
      ENABLE_NETWORK: true
      SANDBOX_PORT: 8194
    volumes:
      - ../../../data/sandbox:/dependencies
    networks:
      - ssrf_proxy_network

  # SSRF 代理
  ssrf_proxy:
    image: ubuntu/squid:latest
    container_name: dify-dev-ssrf-proxy
    restart: always
    ports:
      - "3128:3128"
    volumes:
      - ../../source/docker/ssrf_proxy/squid.conf.template:/etc/squid/squid.conf.template
      - ../../source/docker/ssrf_proxy/docker-entrypoint.sh:/docker-entrypoint-mount.sh
    entrypoint: ["sh", "-c", "cp /docker-entrypoint-mount.sh /docker-entrypoint.sh && sed -i 's/\r$$//' /docker-entrypoint.sh && chmod +x /docker-entrypoint.sh && /docker-entrypoint.sh"]
    environment:
      HTTP_PORT: 3128
      COREDUMP_DIR: /var/spool/squid
    networks:
      - ssrf_proxy_network
      - default

networks:
  ssrf_proxy_network:
    driver: bridge
    internal: true

volumes:
  postgres_data:
  redis_data:
  weaviate_data:
  sandbox_data:
EOF
    
    cd ../../..
    echo -e "${GREEN}✅ 中间件配置完成${NC}"
}

# 配置 API 服务
setup_api() {
    echo -e "${YELLOW}配置 API 服务...${NC}"
    
    cd dify-dev/source/api
    
    # 安装 UV 包管理器
    if ! command -v uv &> /dev/null; then
        pip install uv
    fi
    
    # 创建虚拟环境并安装依赖
    uv sync --dev
    
    # 配置环境变量
    cp .env.example ../../../config/api/.env
    
    # 生成密钥
    SECRET_KEY=$(openssl rand -base64 42)
    sed -i "s/^SECRET_KEY=.*/SECRET_KEY=${SECRET_KEY}/" ../../../config/api/.env
    
    # 配置数据库连接
    cat >> ../../../config/api/.env << 'EOF'

# ==========开发环境配置==========
# 数据库配置
DB_USERNAME=postgres
DB_PASSWORD=difyai123456
DB_HOST=localhost
DB_PORT=5432
DB_DATABASE=dify

# Redis 配置
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=difyai123456
REDIS_DB=0

# 向量数据库配置
VECTOR_STORE=weaviate
WEAVIATE_ENDPOINT=http://localhost:8080

# 沙箱配置
CODE_EXECUTION_ENDPOINT=http://localhost:8194
CODE_EXECUTION_API_KEY=dify-sandbox

# SSRF 代理配置
SSRF_PROXY_HTTP_URL=http://localhost:3128
SSRF_PROXY_HTTPS_URL=http://localhost:3128

# 开发模式配置
DEBUG=true
FLASK_DEBUG=true
LOG_LEVEL=DEBUG

# 服务地址配置
CONSOLE_API_URL=http://localhost:5001/console/api
CONSOLE_WEB_URL=http://localhost:3000
SERVICE_API_URL=http://localhost:5001/api
APP_WEB_URL=http://localhost:3000
EOF
    
    cd ../../..
    echo -e "${GREEN}✅ API 服务配置完成${NC}"
}

# 配置 Web 服务
setup_web() {
    echo -e "${YELLOW}配置 Web 服务...${NC}"
    
    cd dify-dev/source/web
    
    # 安装 pnpm
    if ! command -v pnpm &> /dev/null; then
        npm install -g pnpm
    fi
    
    # 安装依赖
    pnpm install
    
    # 配置环境变量
    cp .env.example ../../../config/web/.env.local
    
    # 配置开发环境变量
    cat > ../../../config/web/.env.local << 'EOF'
# 开发环境配置
NEXT_PUBLIC_DEPLOY_ENV=DEVELOPMENT
NEXT_PUBLIC_EDITION=SELF_HOSTED

# API 地址配置
NEXT_PUBLIC_API_PREFIX=http://localhost:5001/console/api
NEXT_PUBLIC_PUBLIC_API_PREFIX=http://localhost:5001/api

# 其他配置
NEXT_PUBLIC_SENTRY_DSN=
NEXT_TELEMETRY_DISABLED=1
EOF
    
    cd ../../..
    echo -e "${GREEN}✅ Web 服务配置完成${NC}"
}

# 创建管理脚本
create_management_scripts() {
    echo -e "${YELLOW}创建管理脚本...${NC}"
    
    # 创建中间件管理脚本
    cat > dify-dev/scripts/middleware.sh << 'EOF'
#!/bin/bash

# 中间件服务管理脚本
COMPOSE_FILE="../config/middleware/docker-compose.middleware.yml"

case "$1" in
    start)
        echo "启动中间件服务..."
        docker-compose -f $COMPOSE_FILE up -d
        ;;
    stop)
        echo "停止中间件服务..."
        docker-compose -f $COMPOSE_FILE down
        ;;
    restart)
        echo "重启中间件服务..."
        docker-compose -f $COMPOSE_FILE restart
        ;;
    status)
        echo "查看中间件服务状态..."
        docker-compose -f $COMPOSE_FILE ps
        ;;
    logs)
        echo "查看中间件服务日志..."
        docker-compose -f $COMPOSE_FILE logs -f ${2:-}
        ;;
    *)
        echo "用法: $0 {start|stop|restart|status|logs [service]}"
        exit 1
        ;;
esac
EOF

    # 创建 API 服务管理脚本
    cat > dify-dev/scripts/api.sh << 'EOF'
#!/bin/bash

# API 服务管理脚本
API_DIR="../source/api"
ENV_FILE="../config/api/.env"

case "$1" in
    start)
        echo "启动 API 服务..."
        cd $API_DIR
        export $(cat ../../config/api/.env | xargs)
        uv run flask run --host 0.0.0.0 --port 5001 --debug
        ;;
    worker)
        echo "启动 Worker 服务..."
        cd $API_DIR
        export $(cat ../../config/api/.env | xargs)
        uv run celery -A app.celery worker -P gevent -c 1 --loglevel INFO -Q dataset,generation,mail,ops_trace,app_deletion
        ;;
    migrate)
        echo "执行数据库迁移..."
        cd $API_DIR
        export $(cat ../../config/api/.env | xargs)
        uv run flask db upgrade
        ;;
    shell)
        echo "进入 API Shell..."
        cd $API_DIR
        export $(cat ../../config/api/.env | xargs)
        uv run flask shell
        ;;
    test)
        echo "运行测试..."
        cd $API_DIR
        uv run pytest
        ;;
    *)
        echo "用法: $0 {start|worker|migrate|shell|test}"
        exit 1
        ;;
esac
EOF

    # 创建 Web 服务管理脚本
    cat > dify-dev/scripts/web.sh << 'EOF'
#!/bin/bash

# Web 服务管理脚本
WEB_DIR="../source/web"

case "$1" in
    start)
        echo "启动 Web 开发服务..."
        cd $WEB_DIR
        cp ../../config/web/.env.local .env.local
        pnpm dev
        ;;
    build)
        echo "构建 Web 应用..."
        cd $WEB_DIR
        cp ../../config/web/.env.local .env.local
        pnpm build
        ;;
    prod)
        echo "启动 Web 生产服务..."
        cd $WEB_DIR
        cp ../../config/web/.env.local .env.local
        pnpm start
        ;;
    lint)
        echo "代码检查..."
        cd $WEB_DIR
        pnpm lint
        ;;
    test)
        echo "运行测试..."
        cd $WEB_DIR
        pnpm test
        ;;
    *)
        echo "用法: $0 {start|build|prod|lint|test}"
        exit 1
        ;;
esac
EOF

    # 创建主管理脚本
    cat > dify-dev/scripts/dify-dev.sh << 'EOF'
#!/bin/bash

# Dify 开发环境主管理脚本

case "$1" in
    init)
        echo "初始化开发环境..."
        ./middleware.sh start
        sleep 10
        ./api.sh migrate
        echo "✅ 开发环境初始化完成"
        echo "请按以下顺序启动服务："
        echo "1. ./dify-dev.sh start-api"
        echo "2. ./dify-dev.sh start-worker (新终端)"
        echo "3. ./dify-dev.sh start-web (新终端)"
        ;;
    start-middleware)
        ./middleware.sh start
        ;;
    start-api)
        ./api.sh start
        ;;
    start-worker)
        ./api.sh worker
        ;;
    start-web)
        ./web.sh start
        ;;
    stop)
        echo "停止所有服务..."
        ./middleware.sh stop
        pkill -f "flask run"
        pkill -f "celery"
        pkill -f "next dev"
        ;;
    status)
        echo "=== 中间件服务状态 ==="
        ./middleware.sh status
        echo ""
        echo "=== 应用服务状态 ==="
        ps aux | grep -E "(flask|celery|next)" | grep -v grep
        ;;
    logs)
        case "$2" in
            middleware)
                ./middleware.sh logs $3
                ;;
            *)
                echo "用法: $0 logs {middleware [service]}"
                ;;
        esac
        ;;
    *)
        echo "Dify 开发环境管理脚本"
        echo ""
        echo "用法: $0 {init|start-middleware|start-api|start-worker|start-web|stop|status|logs}"
        echo ""
        echo "命令说明:"
        echo "  init              - 初始化开发环境"
        echo "  start-middleware  - 启动中间件服务"
        echo "  start-api         - 启动 API 服务"
        echo "  start-worker      - 启动 Worker 服务"
        echo "  start-web         - 启动 Web 服务"
        echo "  stop              - 停止所有服务"
        echo "  status            - 查看服务状态"
        echo "  logs              - 查看日志"
        echo ""
        echo "开发流程:"
        echo "1. 首次运行: ./dify-dev.sh init"
        echo "2. 启动 API: ./dify-dev.sh start-api"
        echo "3. 启动 Worker: ./dify-dev.sh start-worker (新终端)"
        echo "4. 启动 Web: ./dify-dev.sh start-web (新终端)"
        echo "5. 访问: http://localhost:3000"
        exit 1
        ;;
esac
EOF

    # 设置执行权限
    chmod +x dify-dev/scripts/*.sh
    
    echo -e "${GREEN}✅ 管理脚本创建完成${NC}"
}

# 创建开发环境说明文档
create_dev_guide() {
    echo -e "${YELLOW}创建开发环境说明文档...${NC}"
    
    cat > dify-dev/README.md << 'EOF'
# Dify 开发环境

## 目录结构

```
dify-dev/
├── source/              # 源代码目录
├── data/               # 数据存储目录
│   ├── postgres/       # PostgreSQL 数据
│   ├── redis/          # Redis 数据
│   ├── weaviate/       # Weaviate 数据
│   └── storage/        # 文件存储
├── config/             # 配置文件目录
│   ├── middleware/     # 中间件配置
│   ├── api/           # API 配置
│   └── web/           # Web 配置
├── logs/              # 日志目录
└── scripts/           # 管理脚本
```

## 快速开始

### 1. 初始化环境
```bash
cd dify-dev/scripts
./dify-dev.sh init
```

### 2. 启动服务
```bash
# 终端1: 启动 API 服务
./dify-dev.sh start-api

# 终端2: 启动 Worker 服务
./dify-dev.sh start-worker

# 终端3: 启动 Web 服务
./dify-dev.sh start-web
```

### 3. 访问应用
- Web 界面: http://localhost:3000
- API 文档: http://localhost:5001/console/api/docs

## 开发工作流

### 后端开发
1. 修改 `source/api/` 下的代码
2. API 服务会自动重载 (Flask debug 模式)
3. 查看日志: `./dify-dev.sh logs api`

### 前端开发
1. 修改 `source/web/` 下的代码
2. Web 服务会自动重载 (Next.js dev 模式)
3. 支持热更新和实时预览

### 数据库操作
```bash
# 创建迁移文件
cd source/api
uv run flask db migrate -m "描述"

# 执行迁移
./scripts/api.sh migrate

# 进入数据库
docker exec -it dify-dev-postgres psql -U postgres -d dify
```

### 调试技巧
1. API 调试: 使用 Flask 的 debug 模式
2. 前端调试: 使用浏览器开发者工具
3. 数据库调试: 使用 pgAdmin 或命令行工具

## 常用命令

```bash
# 查看服务状态
./dify-dev.sh status

# 停止所有服务
./dify-dev.sh stop

# 查看中间件日志
./dify-dev.sh logs middleware

# 重启中间件
./middleware.sh restart

# 运行测试
./api.sh test
./web.sh test
```

## 故障排除

### 常见问题
1. **端口冲突**: 确保端口 3000, 5001, 5432, 6379, 8080 未被占用
2. **权限问题**: 确保 Docker 有足够权限
3. **依赖问题**: 重新安装依赖

### 重置环境
```bash
# 停止所有服务
./dify-dev.sh stop

# 清理数据
rm -rf ../data/*

# 重新初始化
./dify-dev.sh init
```
EOF
    
    echo -e "${GREEN}✅ 开发环境说明文档创建完成${NC}"
}

# 主函数
main() {
    check_requirements
    setup_directories
    clone_source
    setup_middleware
    setup_api
    setup_web
    create_management_scripts
    create_dev_guide
    
    echo -e "${GREEN}🎉 Dify 开发环境搭建完成！${NC}"
    echo -e "${YELLOW}请按以下步骤启动开发环境：${NC}"
    echo "1. cd dify-dev/scripts"
    echo "2. ./dify-dev.sh init"
    echo "3. ./dify-dev.sh start-api (新终端)"
    echo "4. ./dify-dev.sh start-worker (新终端)"
    echo "5. ./dify-dev.sh start-web (新终端)"
    echo "6. 访问 http://localhost:3000"
}

# 执行主函数
main "$@" 