#!/bin/bash

# Dify 家庭服务器基础服务部署脚本 (优化版)
# 适用于: Ubuntu 20.04+ 服务器
# 功能: 部署PostgreSQL, Redis, Weaviate, 可选监控系统

set -e

# 版本信息
SCRIPT_VERSION="1.1.0"
SCRIPT_DATE="2024-12-19"

echo "🏠 Dify 家庭服务器部署脚本 v${SCRIPT_VERSION} (优化版)"
echo "📅 ${SCRIPT_DATE}"
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认端口配置 (可通过环境变量或命令行参数修改)
POSTGRES_PORT=${POSTGRES_PORT:-5432}
REDIS_PORT=${REDIS_PORT:-6379}
WEAVIATE_PORT=${WEAVIATE_PORT:-8080}
PROMETHEUS_PORT=${PROMETHEUS_PORT:-9090}
GRAFANA_PORT=${GRAFANA_PORT:-3000}
NODE_EXPORTER_PORT=${NODE_EXPORTER_PORT:-9100}
POSTGRES_EXPORTER_PORT=${POSTGRES_EXPORTER_PORT:-9187}
REDIS_EXPORTER_PORT=${REDIS_EXPORTER_PORT:-9121}

# 配置变量
SERVER_IP=""
POSTGRES_PASSWORD="dify_dev_$(date +%Y%m%d)"
REDIS_PASSWORD="dify_redis_$(date +%Y%m%d)"
WEAVIATE_API_KEY="dify_weaviate_$(openssl rand -hex 16)"
GRAFANA_PASSWORD="dify_admin_$(date +%Y%m%d)"

# 监控系统开关 (默认关闭)
INSTALL_MONITORING=${INSTALL_MONITORING:-false}

# Docker镜像仓库配置
DOCKER_REGISTRY_MIRROR=${DOCKER_REGISTRY_MIRROR:-"https://docker.mirrors.ustc.edu.cn"}
USE_CHINA_MIRROR=${USE_CHINA_MIRROR:-true}

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示帮助信息
show_help() {
    cat << EOF
Dify家庭服务器部署脚本 - 使用说明

用法: $0 [选项]

环境变量配置:
  POSTGRES_PORT=5432          PostgreSQL端口 (默认: 5432)
  REDIS_PORT=6379             Redis端口 (默认: 6379)
  WEAVIATE_PORT=8080          Weaviate端口 (默认: 8080)
  PROMETHEUS_PORT=9090        Prometheus端口 (默认: 9090)
  GRAFANA_PORT=3000           Grafana端口 (默认: 3000)
  NODE_EXPORTER_PORT=9100     Node Exporter端口 (默认: 9100)
  POSTGRES_EXPORTER_PORT=9187 PostgreSQL Exporter端口 (默认: 9187)
  REDIS_EXPORTER_PORT=9121    Redis Exporter端口 (默认: 9121)
  INSTALL_MONITORING=true     是否安装监控系统 (默认: false)
  USE_CHINA_MIRROR=true       是否使用中国镜像源 (默认: true)

命令行选项:
  --monitoring                启用监控系统安装
  --no-china-mirror          不使用中国镜像源
  --help                     显示此帮助信息

示例:
  # 使用默认配置
  ./home-server-setup-optimized.sh
  
  # 启用监控系统
  INSTALL_MONITORING=true ./home-server-setup-optimized.sh
  
  # 自定义端口
  POSTGRES_PORT=15432 REDIS_PORT=16379 ./home-server-setup-optimized.sh
  
  # 使用命令行参数
  ./home-server-setup-optimized.sh --monitoring --no-china-mirror

EOF
}

# 解析命令行参数
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --monitoring)
                INSTALL_MONITORING=true
                shift
                ;;
            --no-china-mirror)
                USE_CHINA_MIRROR=false
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 显示配置信息
show_configuration() {
    echo "=== 部署配置 ==="
    echo "PostgreSQL端口: ${POSTGRES_PORT}"
    echo "Redis端口: ${REDIS_PORT}"
    echo "Weaviate端口: ${WEAVIATE_PORT}"
    if [ "$INSTALL_MONITORING" = true ]; then
        echo "Prometheus端口: ${PROMETHEUS_PORT}"
        echo "Grafana端口: ${GRAFANA_PORT}"
        echo "Node Exporter端口: ${NODE_EXPORTER_PORT}"
        echo "PostgreSQL Exporter端口: ${POSTGRES_EXPORTER_PORT}"
        echo "Redis Exporter端口: ${REDIS_EXPORTER_PORT}"
    fi
    echo "安装监控系统: ${INSTALL_MONITORING}"
    echo "使用中国镜像源: ${USE_CHINA_MIRROR}"
    echo ""
    
    read -p "确认以上配置并继续部署? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "部署已取消"
        exit 0
    fi
}

# 检测服务器IP
detect_server_ip() {
    log_info "检测服务器IP地址..."
    
    # 尝试多种方法获取IP
    if command -v hostname &> /dev/null; then
        SERVER_IP=$(hostname -I | awk '{print $1}')
    fi
    
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP=$(ip route get 1 | awk '{print $7; exit}' 2>/dev/null || true)
    fi
    
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d'/' -f1)
    fi
    
    if [ -z "$SERVER_IP" ]; then
        log_error "无法自动检测服务器IP，请手动输入"
        read -p "请输入服务器IP地址: " SERVER_IP
    fi
    
    # 验证IP格式
    if ! echo "$SERVER_IP" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
        log_error "无效的IP地址格式: $SERVER_IP"
        exit 1
    fi
    
    log_success "服务器IP: ${SERVER_IP}"
}

# 检查端口冲突
check_port_conflicts() {
    log_info "检查端口冲突..."
    
    local ports=($POSTGRES_PORT $REDIS_PORT $WEAVIATE_PORT)
    if [ "$INSTALL_MONITORING" = true ]; then
        ports+=($PROMETHEUS_PORT $GRAFANA_PORT $NODE_EXPORTER_PORT $POSTGRES_EXPORTER_PORT $REDIS_EXPORTER_PORT)
    fi
    
    local conflicts=()
    for port in "${ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":${port} " || ss -tuln 2>/dev/null | grep -q ":${port} "; then
            conflicts+=($port)
        fi
    done
    
    if [ ${#conflicts[@]} -gt 0 ]; then
        log_error "以下端口已被占用: ${conflicts[*]}"
        log_error "请修改端口配置或停止占用端口的服务"
        exit 1
    fi
    
    log_success "端口检查通过"
}

# 检查系统要求
check_requirements() {
    log_info "检查系统要求..."
    
    # 检查操作系统
    if ! command -v lsb_release &> /dev/null; then
        log_error "无法检测操作系统版本，请确保运行在Ubuntu系统上"
        exit 1
    fi
    
    OS_VERSION=$(lsb_release -rs)
    if ! lsb_release -d | grep -q "Ubuntu"; then
        log_error "此脚本仅支持Ubuntu系统"
        exit 1
    fi
    
    # 修复：使用更兼容的版本比较方法
    if [ "$(echo "$OS_VERSION 20.04" | awk '{print ($1 < $2)}')" -eq 1 ]; then
        log_error "需要Ubuntu 20.04或更高版本，当前版本: $OS_VERSION"
        exit 1
    fi
    
    log_success "操作系统检查通过: Ubuntu $OS_VERSION"
    
    # 检查权限
    if [ "$EUID" -eq 0 ]; then
        log_error "请不要使用root用户运行此脚本"
        exit 1
    fi
    
    # 检查sudo权限
    if ! sudo -n true 2>/dev/null; then
        log_error "需要sudo权限，请确保当前用户在sudo组中"
        exit 1
    fi
    
    log_success "权限检查通过"
    
    # 检查内存 (建议至少4GB)
    TOTAL_MEM_GB=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_MEM_GB" -lt 4 ]; then
        log_warning "内存不足4GB，可能影响性能。当前内存: ${TOTAL_MEM_GB}GB"
        read -p "是否继续安装? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log_success "内存检查通过: ${TOTAL_MEM_GB}GB"
    fi
    
    # 检查磁盘空间 (建议至少20GB可用)
    AVAILABLE_GB=$(df / | awk 'NR==2{printf "%.0f", $4/1024/1024}')
    if [ "$AVAILABLE_GB" -lt 20 ]; then
        log_warning "可用磁盘空间不足20GB，可能影响使用。当前可用: ${AVAILABLE_GB}GB"
        read -p "是否继续安装? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log_success "磁盘空间检查通过: ${AVAILABLE_GB}GB可用"
    fi
    
    # 检查网络连接
    if ! curl -s --connect-timeout 5 https://www.baidu.com > /dev/null; then
        if ! curl -s --connect-timeout 5 https://www.google.com > /dev/null; then
            log_error "无法连接到互联网，请检查网络设置"
            exit 1
        fi
    fi
    
    log_success "网络连接检查通过"
}

# 配置Docker镜像源
configure_docker_mirror() {
    if [ "$USE_CHINA_MIRROR" = true ]; then
        log_info "配置Docker中国镜像源..."
        
        # 创建Docker配置目录
        sudo mkdir -p /etc/docker
        
        # 配置Docker镜像源
        sudo tee /etc/docker/daemon.json > /dev/null << EOF
{
    "registry-mirrors": [
        "https://docker.mirrors.ustc.edu.cn",
        "https://hub-mirror.c.163.com",
        "https://mirror.baidubce.com",
        "https://ccr.ccs.tencentyun.com"
    ],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    }
}
EOF
        
        log_success "Docker镜像源配置完成"
    else
        log_info "使用默认Docker镜像源"
    fi
}

# 安装必要的工具和Docker
install_dependencies() {
    log_info "安装系统依赖和Docker..."
    
    # 更新包列表
    sudo apt update
    
    # 安装基础工具
    sudo apt install -y \
        curl \
        wget \
        git \
        vim \
        htop \
        unzip \
        jq \
        ca-certificates \
        gnupg \
        lsb-release \
        apt-transport-https \
        software-properties-common \
        net-tools
    
    log_success "基础工具安装完成"
    
    # 检查Docker是否已安装
    if command -v docker &> /dev/null; then
        log_success "Docker已安装: $(docker --version)"
    else
        log_info "安装Docker..."
        
        if [ "$USE_CHINA_MIRROR" = true ]; then
            # 使用阿里云Docker安装脚本
            curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
        else
            # 使用官方安装方法
            # 添加Docker官方GPG密钥
            sudo mkdir -p /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            sudo chmod a+r /etc/apt/keyrings/docker.gpg
            
            # 添加Docker仓库
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
              $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            # 安装Docker
            sudo apt update
            sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        fi
        
        # 将当前用户添加到docker组
        sudo usermod -aG docker $USER
        
        log_success "Docker安装完成"
        log_warning "请注意：需要重新登录或重启才能使用Docker命令"
    fi
    
    # 配置Docker镜像源
    configure_docker_mirror
    
    # 重启Docker服务以应用配置
    sudo systemctl restart docker
    sudo systemctl enable docker
    
    # 等待Docker服务启动
    sleep 5
    
    # 检查Docker Compose是否可用
    if docker compose version &> /dev/null; then
        log_success "Docker Compose可用: $(docker compose version --short)"
    else
        log_error "Docker Compose不可用，请检查Docker安装"
        exit 1
    fi
    
    log_success "Docker服务已启动并配置完成"
}

# 创建项目目录结构
setup_directories() {
    log_info "创建项目目录结构..."
    
    # 创建主目录
    sudo mkdir -p /opt/dify-server/{data,config,logs,backups,scripts}
    
    # 创建数据目录
    sudo mkdir -p /opt/dify-server/data/{postgres,redis,weaviate}
    
    # 创建配置目录
    sudo mkdir -p /opt/dify-server/config/{postgres,redis,weaviate}
    
    # 创建日志目录
    sudo mkdir -p /opt/dify-server/logs/{postgres,redis,weaviate}
    
    if [ "$INSTALL_MONITORING" = true ]; then
        sudo mkdir -p /opt/dify-server/data/{prometheus,grafana}
        sudo mkdir -p /opt/dify-server/config/monitoring
        sudo mkdir -p /opt/dify-server/logs/monitoring
    fi
    
    # 设置目录权限
    sudo chown -R $USER:$USER /opt/dify-server
    chmod -R 755 /opt/dify-server
    
    log_success "目录结构创建完成"
}

# 创建Docker网络
create_docker_network() {
    log_info "创建Docker网络..."
    
    # 删除已存在的网络（如果有）
    docker network rm dify-network 2>/dev/null || true
    
    # 创建自定义网络
    docker network create dify-network
    log_success "Docker网络 'dify-network' 创建完成"
}

# 部署PostgreSQL数据库
deploy_postgres() {
    log_info "部署PostgreSQL数据库..."
    
    # 选择镜像源
    local postgres_image="postgres:15-alpine"
    if [ "$USE_CHINA_MIRROR" = true ]; then
        # 尝试拉取国内镜像
        docker pull "${postgres_image}" 2>/dev/null || {
            log_warning "无法拉取官方镜像，使用默认配置"
        }
    fi
    
    # 创建PostgreSQL配置文件
    cat > /opt/dify-server/config/postgres/docker-compose.yml << EOF
version: '3.8'

services:
  postgres:
    image: ${postgres_image}
    container_name: dify-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: dify
      POSTGRES_USER: dify
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      PGDATA: /var/lib/postgresql/data/pgdata
    ports:
      - "${SERVER_IP}:${POSTGRES_PORT}:5432"
    volumes:
      - /opt/dify-server/data/postgres:/var/lib/postgresql/data
    command: >
      postgres 
      -c max_connections=200
      -c shared_buffers=256MB
      -c effective_cache_size=1GB
      -c work_mem=4MB
      -c maintenance_work_mem=64MB
      -c checkpoint_completion_target=0.9
      -c wal_buffers=16MB
      -c default_statistics_target=100
      -c random_page_cost=1.1
      -c effective_io_concurrency=200
      -c log_destination=stderr
      -c logging_collector=off
      -c log_statement=none
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U dify -d dify"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - dify-network

networks:
  dify-network:
    external: true
EOF
    
    # 启动PostgreSQL
    cd /opt/dify-server/config/postgres
    docker compose up -d
    
    # 等待PostgreSQL启动
    log_info "等待PostgreSQL启动..."
    local retry_count=0
    local max_retries=30
    
    while [ $retry_count -lt $max_retries ]; do
        if docker exec dify-postgres pg_isready -U dify -d dify > /dev/null 2>&1; then
            break
        fi
        sleep 2
        retry_count=$((retry_count + 1))
    done
    
    if [ $retry_count -eq $max_retries ]; then
        log_error "PostgreSQL启动超时"
        docker logs dify-postgres
        exit 1
    fi
    
    log_success "PostgreSQL部署完成 (端口: ${POSTGRES_PORT})"
}

# 部署Redis缓存
deploy_redis() {
    log_info "部署Redis缓存..."
    
    # 选择镜像源
    local redis_image="redis:7-alpine"
    if [ "$USE_CHINA_MIRROR" = true ]; then
        docker pull "${redis_image}" 2>/dev/null || {
            log_warning "无法拉取官方镜像，使用默认配置"
        }
    fi
    
    # 创建Redis配置文件
    cat > /opt/dify-server/config/redis/redis.conf << EOF
# Redis配置文件
bind 0.0.0.0
port 6379
requirepass ${REDIS_PASSWORD}

# 内存管理
maxmemory 1gb
maxmemory-policy allkeys-lru

# 持久化
save 900 1
save 300 10
save 60 10000
appendonly yes
appendfsync everysec

# 日志
loglevel notice
logfile ""

# 安全
protected-mode no

# 性能优化
tcp-keepalive 300
timeout 0
EOF
    
    # 创建Redis Docker Compose文件
    cat > /opt/dify-server/config/redis/docker-compose.yml << EOF
version: '3.8'

services:
  redis:
    image: ${redis_image}
    container_name: dify-redis
    restart: unless-stopped
    ports:
      - "${SERVER_IP}:${REDIS_PORT}:6379"
    volumes:
      - /opt/dify-server/data/redis:/data
      - /opt/dify-server/config/redis/redis.conf:/usr/local/etc/redis/redis.conf
    command: redis-server /usr/local/etc/redis/redis.conf
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - dify-network

networks:
  dify-network:
    external: true
EOF
    
    # 启动Redis
    cd /opt/dify-server/config/redis
    docker compose up -d
    
    # 等待Redis启动
    log_info "等待Redis启动..."
    local retry_count=0
    local max_retries=20
    
    while [ $retry_count -lt $max_retries ]; do
        if docker exec dify-redis redis-cli -a "${REDIS_PASSWORD}" ping > /dev/null 2>&1; then
            break
        fi
        sleep 2
        retry_count=$((retry_count + 1))
    done
    
    if [ $retry_count -eq $max_retries ]; then
        log_error "Redis启动超时"
        docker logs dify-redis
        exit 1
    fi
    
    log_success "Redis部署完成 (端口: ${REDIS_PORT})"
}

# 部署Weaviate向量数据库
deploy_weaviate() {
    log_info "部署Weaviate向量数据库..."
    
    # 选择镜像源
    local weaviate_image="semitechnologies/weaviate:1.19.0"
    if [ "$USE_CHINA_MIRROR" = true ]; then
        docker pull "${weaviate_image}" 2>/dev/null || {
            log_warning "无法拉取官方镜像，使用默认配置"
        }
    fi
    
    # 创建Weaviate Docker Compose文件
    cat > /opt/dify-server/config/weaviate/docker-compose.yml << EOF
version: '3.8'

services:
  weaviate:
    image: ${weaviate_image}
    container_name: dify-weaviate
    restart: unless-stopped
    ports:
      - "${SERVER_IP}:${WEAVIATE_PORT}:8080"
    volumes:
      - /opt/dify-server/data/weaviate:/var/lib/weaviate
    environment:
      PERSISTENCE_DATA_PATH: '/var/lib/weaviate'
      QUERY_DEFAULTS_LIMIT: 25
      AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED: 'false'
      AUTHENTICATION_APIKEY_ENABLED: 'true'
      AUTHENTICATION_APIKEY_ALLOWED_KEYS: '${WEAVIATE_API_KEY}'
      AUTHENTICATION_APIKEY_USERS: 'dify@localhost'
      AUTHORIZATION_ADMINLIST_ENABLED: 'true'
      AUTHORIZATION_ADMINLIST_USERS: 'dify@localhost'
      DEFAULT_VECTORIZER_MODULE: 'none'
      CLUSTER_HOSTNAME: 'node1'
      LOG_LEVEL: 'info'
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/v1/.well-known/ready"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
    networks:
      - dify-network

networks:
  dify-network:
    external: true
EOF
    
    # 启动Weaviate
    cd /opt/dify-server/config/weaviate
    docker compose up -d
    
    # 等待Weaviate启动
    log_info "等待Weaviate启动..."
    local retry_count=0
    local max_retries=40
    
    while [ $retry_count -lt $max_retries ]; do
        if curl -s -f "http://${SERVER_IP}:${WEAVIATE_PORT}/v1/.well-known/ready" > /dev/null 2>&1; then
            break
        fi
        sleep 3
        retry_count=$((retry_count + 1))
    done
    
    if [ $retry_count -eq $max_retries ]; then
        log_error "Weaviate启动超时"
        docker logs dify-weaviate
        exit 1
    fi
    
    log_success "Weaviate部署完成 (端口: ${WEAVIATE_PORT})"
}

# 部署监控系统
deploy_monitoring() {
    if [ "$INSTALL_MONITORING" != true ]; then
        log_info "跳过监控系统部署 (未启用)"
        return
    fi
    
    log_info "部署监控系统..."
    
    # 选择镜像源
    local prometheus_image="prom/prometheus:latest"
    local grafana_image="grafana/grafana:latest"
    local node_exporter_image="prom/node-exporter:latest"
    local postgres_exporter_image="prometheuscommunity/postgres-exporter:latest"
    local redis_exporter_image="oliver006/redis_exporter:latest"
    
    if [ "$USE_CHINA_MIRROR" = true ]; then
        # 预拉取镜像
        for image in "$prometheus_image" "$grafana_image" "$node_exporter_image" "$postgres_exporter_image" "$redis_exporter_image"; do
            docker pull "$image" 2>/dev/null || {
                log_warning "无法拉取镜像: $image"
            }
        done
    fi
    
    # 创建Prometheus配置文件
    cat > /opt/dify-server/config/monitoring/prometheus.yml << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'postgres-exporter'
    static_configs:
      - targets: ['postgres-exporter:9187']
    scrape_interval: 30s

  - job_name: 'redis-exporter'
    static_configs:
      - targets: ['redis-exporter:9121']
    scrape_interval: 30s
EOF
    
    # 创建监控系统Docker Compose文件
    cat > /opt/dify-server/config/monitoring/docker-compose.yml << EOF
version: '3.8'

services:
  prometheus:
    image: ${prometheus_image}
    container_name: dify-prometheus
    restart: unless-stopped
    ports:
      - "${SERVER_IP}:${PROMETHEUS_PORT}:9090"
    volumes:
      - /opt/dify-server/config/monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
      - /opt/dify-server/data/prometheus:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
      - '--web.enable-lifecycle'
      - '--storage.tsdb.retention.time=15d'
    networks:
      - dify-network

  grafana:
    image: ${grafana_image}
    container_name: dify-grafana
    restart: unless-stopped
    ports:
      - "${SERVER_IP}:${GRAFANA_PORT}:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD}
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_INSTALL_PLUGINS=grafana-piechart-panel
    volumes:
      - /opt/dify-server/data/grafana:/var/lib/grafana
    networks:
      - dify-network

  node-exporter:
    image: ${node_exporter_image}
    container_name: dify-node-exporter
    restart: unless-stopped
    ports:
      - "${SERVER_IP}:${NODE_EXPORTER_PORT}:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.ignored-mount-points=^/(sys|proc|dev|host|etc)($$|/)'
    networks:
      - dify-network

  postgres-exporter:
    image: ${postgres_exporter_image}
    container_name: dify-postgres-exporter
    restart: unless-stopped
    ports:
      - "${SERVER_IP}:${POSTGRES_EXPORTER_PORT}:9187"
    environment:
      DATA_SOURCE_NAME: "postgresql://dify:${POSTGRES_PASSWORD}@dify-postgres:5432/dify?sslmode=disable"
    networks:
      - dify-network
    depends_on:
      - prometheus

  redis-exporter:
    image: ${redis_exporter_image}
    container_name: dify-redis-exporter
    restart: unless-stopped
    ports:
      - "${SERVER_IP}:${REDIS_EXPORTER_PORT}:9121"
    environment:
      REDIS_ADDR: "redis://dify-redis:6379"
      REDIS_PASSWORD: "${REDIS_PASSWORD}"
    networks:
      - dify-network
    depends_on:
      - prometheus

networks:
  dify-network:
    external: true
EOF
    
    # 启动监控系统
    cd /opt/dify-server/config/monitoring
    docker compose up -d
    
    # 等待监控系统启动
    log_info "等待监控系统启动..."
    sleep 30
    
    log_success "监控系统部署完成"
    log_info "Prometheus: http://${SERVER_IP}:${PROMETHEUS_PORT}"
    log_info "Grafana: http://${SERVER_IP}:${GRAFANA_PORT} (admin/${GRAFANA_PASSWORD})"
}

# 创建管理脚本
create_management_scripts() {
    log_info "创建管理脚本..."
    
    # 创建主管理脚本
    cat > /opt/dify-server/scripts/dify-server.sh << EOF
#!/bin/bash

# Dify家庭服务器管理脚本
SCRIPT_DIR="/opt/dify-server"

# 读取配置
POSTGRES_PORT=${POSTGRES_PORT}
REDIS_PORT=${REDIS_PORT}
WEAVIATE_PORT=${WEAVIATE_PORT}
PROMETHEUS_PORT=${PROMETHEUS_PORT}
GRAFANA_PORT=${GRAFANA_PORT}
NODE_EXPORTER_PORT=${NODE_EXPORTER_PORT}
POSTGRES_EXPORTER_PORT=${POSTGRES_EXPORTER_PORT}
REDIS_EXPORTER_PORT=${REDIS_EXPORTER_PORT}
INSTALL_MONITORING=${INSTALL_MONITORING}

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "\${BLUE}[INFO]\${NC} \$1"
}

log_success() {
    echo -e "\${GREEN}[SUCCESS]\${NC} \$1"
}

log_warning() {
    echo -e "\${YELLOW}[WARNING]\${NC} \$1"
}

log_error() {
    echo -e "\${RED}[ERROR]\${NC} \$1"
}

# 启动所有服务
start_services() {
    log_info "启动所有服务..."
    
    cd \${SCRIPT_DIR}/config/postgres && docker compose up -d
    sleep 10
    cd \${SCRIPT_DIR}/config/redis && docker compose up -d
    sleep 10
    cd \${SCRIPT_DIR}/config/weaviate && docker compose up -d
    sleep 15
    
    if [ "\$INSTALL_MONITORING" = true ]; then
        cd \${SCRIPT_DIR}/config/monitoring && docker compose up -d
    fi
    
    log_success "所有服务已启动"
}

# 停止所有服务
stop_services() {
    log_info "停止所有服务..."
    
    if [ "\$INSTALL_MONITORING" = true ]; then
        cd \${SCRIPT_DIR}/config/monitoring && docker compose down
    fi
    cd \${SCRIPT_DIR}/config/weaviate && docker compose down
    cd \${SCRIPT_DIR}/config/redis && docker compose down
    cd \${SCRIPT_DIR}/config/postgres && docker compose down
    
    log_success "所有服务已停止"
}

# 重启所有服务
restart_services() {
    log_info "重启所有服务..."
    stop_services
    sleep 10
    start_services
}

# 查看服务状态
show_status() {
    echo "=== Dify服务器状态 ==="
    echo ""
    echo "Docker容器状态:"
    docker ps --format "table {{.Names}}\\t{{.Status}}\\t{{.Ports}}" | grep dify
    echo ""
    echo "端口使用情况:"
    echo "PostgreSQL: \${POSTGRES_PORT}"
    echo "Redis: \${REDIS_PORT}"
    echo "Weaviate: \${WEAVIATE_PORT}"
    if [ "\$INSTALL_MONITORING" = true ]; then
        echo "Prometheus: \${PROMETHEUS_PORT}"
        echo "Grafana: \${GRAFANA_PORT}"
        echo "Node Exporter: \${NODE_EXPORTER_PORT}"
        echo "PostgreSQL Exporter: \${POSTGRES_EXPORTER_PORT}"
        echo "Redis Exporter: \${REDIS_EXPORTER_PORT}"
    fi
    echo ""
    echo "磁盘使用情况:"
    df -h | grep -E "(Filesystem|/opt/dify-server|/$)"
    echo ""
    echo "内存使用情况:"
    free -h
    echo ""
    echo "CPU负载:"
    uptime
}

# 查看服务日志
show_logs() {
    local service=\$1
    case "\$service" in
        postgres)
            docker logs -f dify-postgres
            ;;
        redis)
            docker logs -f dify-redis
            ;;
        weaviate)
            docker logs -f dify-weaviate
            ;;
        prometheus)
            if [ "\$INSTALL_MONITORING" = true ]; then
                docker logs -f dify-prometheus
            else
                log_error "监控系统未安装"
            fi
            ;;
        grafana)
            if [ "\$INSTALL_MONITORING" = true ]; then
                docker logs -f dify-grafana
            else
                log_error "监控系统未安装"
            fi
            ;;
        *)
            log_error "未知服务: \$service"
            if [ "\$INSTALL_MONITORING" = true ]; then
                echo "可用服务: postgres, redis, weaviate, prometheus, grafana"
            else
                echo "可用服务: postgres, redis, weaviate"
            fi
            ;;
    esac
}

# 数据备份
backup_data() {
    log_info "执行数据备份..."
    
    BACKUP_DATE=\$(date +%Y%m%d_%H%M%S)
    BACKUP_DIR="\${SCRIPT_DIR}/backups/\${BACKUP_DATE}"
    mkdir -p "\$BACKUP_DIR"
    
    # 备份PostgreSQL
    log_info "备份PostgreSQL数据库..."
    if docker exec dify-postgres pg_dump -U dify dify > "\${BACKUP_DIR}/postgres_backup.sql"; then
        log_success "PostgreSQL备份完成"
    else
        log_error "PostgreSQL备份失败"
    fi
    
    # 备份Redis
    log_info "备份Redis数据..."
    if docker exec dify-redis redis-cli --rdb "\${BACKUP_DIR}/redis_backup.rdb" 2>/dev/null; then
        log_success "Redis备份完成"
    else
        log_warning "Redis备份可能失败，手动复制数据文件"
        cp -r "\${SCRIPT_DIR}/data/redis" "\${BACKUP_DIR}/redis_data_backup" 2>/dev/null || true
    fi
    
    # 备份Weaviate数据
    log_info "备份Weaviate数据..."
    if tar -czf "\${BACKUP_DIR}/weaviate_backup.tar.gz" -C "\${SCRIPT_DIR}/data" weaviate 2>/dev/null; then
        log_success "Weaviate备份完成"
    else
        log_warning "Weaviate备份失败"
    fi
    
    # 备份配置文件
    log_info "备份配置文件..."
    if tar -czf "\${BACKUP_DIR}/config_backup.tar.gz" -C "\${SCRIPT_DIR}" config; then
        log_success "配置文件备份完成"
    else
        log_warning "配置文件备份失败"
    fi
    
    # 创建备份报告
    cat > "\${BACKUP_DIR}/backup_report.txt" << EOL
Dify服务器备份报告
备份时间: \$(date)
备份目录: \${BACKUP_DIR}

备份内容:
- PostgreSQL: postgres_backup.sql
- Redis: redis_backup.rdb 或 redis_data_backup/
- Weaviate: weaviate_backup.tar.gz
- 配置文件: config_backup.tar.gz

备份大小:
\$(du -sh "\${BACKUP_DIR}")
EOL
    
    log_success "备份完成: \${BACKUP_DIR}"
    
    # 清理旧备份 (保留最近7天)
    find "\${SCRIPT_DIR}/backups" -type d -mtime +7 -exec rm -rf {} \\; 2>/dev/null || true
}

# 显示连接信息
show_info() {
    local SERVER_IP=\$(hostname -I | awk '{print \$1}')
    
    echo "=== Dify家庭服务器连接信息 ==="
    echo ""
    echo "服务器IP: \${SERVER_IP}"
    echo ""
    echo "数据库连接:"
    echo "  PostgreSQL: \${SERVER_IP}:\${POSTGRES_PORT}"
    echo "  数据库名: dify"
    echo "  用户名: dify"
    echo "  密码: 见 \${SCRIPT_DIR}/connection-info.txt"
    echo ""
    echo "  Redis: \${SERVER_IP}:\${REDIS_PORT}"
    echo "  密码: 见 \${SCRIPT_DIR}/connection-info.txt"
    echo ""
    echo "  Weaviate: http://\${SERVER_IP}:\${WEAVIATE_PORT}"
    echo "  API Key: 见 \${SCRIPT_DIR}/connection-info.txt"
    echo ""
    
    if [ "\$INSTALL_MONITORING" = true ]; then
        echo "监控面板:"
        echo "  Prometheus: http://\${SERVER_IP}:\${PROMETHEUS_PORT}"
        echo "  Grafana: http://\${SERVER_IP}:\${GRAFANA_PORT}"
        echo "  用户名: admin"
        echo "  密码: 见 \${SCRIPT_DIR}/connection-info.txt"
        echo ""
    fi
}

# 健康检查
health_check() {
    log_info "执行健康检查..."
    
    local all_healthy=true
    local SERVER_IP=\$(hostname -I | awk '{print \$1}')
    
    # 读取密码
    local REDIS_PASSWORD=\$(grep "REDIS_PASSWORD=" "\${SCRIPT_DIR}/connection-info.txt" | cut -d'=' -f2 | xargs)
    
    # 检查PostgreSQL
    if docker exec dify-postgres pg_isready -U dify -d dify > /dev/null 2>&1; then
        log_success "PostgreSQL: 健康"
    else
        log_error "PostgreSQL: 异常"
        all_healthy=false
    fi
    
    # 检查Redis
    if docker exec dify-redis redis-cli -a "\${REDIS_PASSWORD}" ping > /dev/null 2>&1; then
        log_success "Redis: 健康"
    else
        log_error "Redis: 异常"
        all_healthy=false
    fi
    
    # 检查Weaviate
    if curl -s -f "http://\${SERVER_IP}:\${WEAVIATE_PORT}/v1/.well-known/ready" > /dev/null 2>&1; then
        log_success "Weaviate: 健康"
    else
        log_error "Weaviate: 异常"
        all_healthy=false
    fi
    
    if [ "\$INSTALL_MONITORING" = true ]; then
        # 检查监控服务
        if curl -s -f "http://\${SERVER_IP}:\${PROMETHEUS_PORT}/-/healthy" > /dev/null 2>&1; then
            log_success "Prometheus: 健康"
        else
            log_warning "Prometheus: 异常或正在启动"
        fi
        
        if curl -s -f "http://\${SERVER_IP}:\${GRAFANA_PORT}/api/health" > /dev/null 2>&1; then
            log_success "Grafana: 健康"
        else
            log_warning "Grafana: 可能正在启动中"
        fi
    fi
    
    if [ "\$all_healthy" = true ]; then
        log_success "所有核心服务运行正常"
        return 0
    else
        log_error "部分服务异常，请检查日志"
        return 1
    fi
}

# 主函数
case "\$1" in
    start)
        start_services
        ;;
    stop)
        stop_services
        ;;
    restart)
        restart_services
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs "\$2"
        ;;
    backup)
        backup_data
        ;;
    info)
        show_info
        ;;
    health)
        health_check
        ;;
    *)
        echo "Dify家庭服务器管理脚本"
        echo ""
        echo "用法: \$0 {start|stop|restart|status|logs|backup|info|health}"
        echo ""
        echo "命令说明:"
        echo "  start    - 启动所有服务"
        echo "  stop     - 停止所有服务"
        echo "  restart  - 重启所有服务"
        echo "  status   - 查看服务状态"
        echo "  logs     - 查看服务日志 (需指定服务名)"
        echo "  backup   - 执行数据备份"
        echo "  info     - 显示连接信息"
        echo "  health   - 健康检查"
        echo ""
        echo "示例:"
        echo "  \$0 start          # 启动所有服务"
        echo "  \$0 logs postgres  # 查看PostgreSQL日志"
        echo "  \$0 backup         # 备份数据"
        echo "  \$0 health         # 检查服务健康状态"
        exit 1
        ;;
esac
EOF
    
    chmod +x /opt/dify-server/scripts/dify-server.sh
    
    # 创建软链接到系统PATH
    sudo ln -sf /opt/dify-server/scripts/dify-server.sh /usr/local/bin/dify-server
    
    log_success "管理脚本创建完成"
}

# 创建连接信息文件
create_connection_info() {
    log_info "创建连接信息文件..."
    
    cat > /opt/dify-server/connection-info.txt << EOF
# Dify家庭服务器连接信息
# 生成时间: $(date)
# 脚本版本: ${SCRIPT_VERSION}

=== 服务器信息 ===
服务器IP: ${SERVER_IP}
操作系统: $(lsb_release -d | cut -f2)
内核版本: $(uname -r)

=== 端口配置 ===
PostgreSQL端口: ${POSTGRES_PORT}
Redis端口: ${REDIS_PORT}
Weaviate端口: ${WEAVIATE_PORT}
EOF

    if [ "$INSTALL_MONITORING" = true ]; then
        cat >> /opt/dify-server/connection-info.txt << EOF
Prometheus端口: ${PROMETHEUS_PORT}
Grafana端口: ${GRAFANA_PORT}
Node Exporter端口: ${NODE_EXPORTER_PORT}
PostgreSQL Exporter端口: ${POSTGRES_EXPORTER_PORT}
Redis Exporter端口: ${REDIS_EXPORTER_PORT}
EOF
    fi

    cat >> /opt/dify-server/connection-info.txt << EOF

=== 数据库连接信息 ===
PostgreSQL:
  主机: ${SERVER_IP}
  端口: ${POSTGRES_PORT}
  数据库: dify
  用户名: dify
  密码: ${POSTGRES_PASSWORD}
  连接字符串: postgresql://dify:${POSTGRES_PASSWORD}@${SERVER_IP}:${POSTGRES_PORT}/dify

Redis:
  主机: ${SERVER_IP}
  端口: ${REDIS_PORT}
  密码: ${REDIS_PASSWORD}
  连接字符串: redis://:${REDIS_PASSWORD}@${SERVER_IP}:${REDIS_PORT}

Weaviate:
  主机: ${SERVER_IP}
  端口: ${WEAVIATE_PORT}
  端点: http://${SERVER_IP}:${WEAVIATE_PORT}
  API Key: ${WEAVIATE_API_KEY}
  用户: dify@localhost
EOF

    if [ "$INSTALL_MONITORING" = true ]; then
        cat >> /opt/dify-server/connection-info.txt << EOF

=== 监控访问地址 ===
Prometheus: http://${SERVER_IP}:${PROMETHEUS_PORT}
Grafana: http://${SERVER_IP}:${GRAFANA_PORT}
  用户名: admin
  密码: ${GRAFANA_PASSWORD}

Node Exporter: http://${SERVER_IP}:${NODE_EXPORTER_PORT}
Postgres Exporter: http://${SERVER_IP}:${POSTGRES_EXPORTER_PORT}
Redis Exporter: http://${SERVER_IP}:${REDIS_EXPORTER_PORT}
EOF
    fi

    cat >> /opt/dify-server/connection-info.txt << EOF

=== 管理命令 ===
启动服务: dify-server start
停止服务: dify-server stop
查看状态: dify-server status
健康检查: dify-server health
数据备份: dify-server backup
查看信息: dify-server info

=== 开发环境配置 ===
在其他开发机器的环境配置文件中使用以下变量:

# 数据库配置
DB_HOST=${SERVER_IP}
DB_PORT=${POSTGRES_PORT}
DB_USERNAME=dify
DB_PASSWORD=${POSTGRES_PASSWORD}
DB_DATABASE=dify

# Redis配置
REDIS_HOST=${SERVER_IP}
REDIS_PORT=${REDIS_PORT}
REDIS_PASSWORD=${REDIS_PASSWORD}

# 向量数据库配置
VECTOR_STORE=weaviate
WEAVIATE_ENDPOINT=http://${SERVER_IP}:${WEAVIATE_PORT}
WEAVIATE_API_KEY=${WEAVIATE_API_KEY}

=== 防火墙端口配置提醒 ===
请确保以下端口在防火墙中开放:
- SSH: 22
- PostgreSQL: ${POSTGRES_PORT}
- Redis: ${REDIS_PORT}  
- Weaviate: ${WEAVIATE_PORT}
EOF

    if [ "$INSTALL_MONITORING" = true ]; then
        cat >> /opt/dify-server/connection-info.txt << EOF
- Prometheus: ${PROMETHEUS_PORT}
- Grafana: ${GRAFANA_PORT}
- Node Exporter: ${NODE_EXPORTER_PORT}
- PostgreSQL Exporter: ${POSTGRES_EXPORTER_PORT}
- Redis Exporter: ${REDIS_EXPORTER_PORT}
EOF
    fi

    cat >> /opt/dify-server/connection-info.txt << EOF

示例防火墙配置命令:
sudo ufw allow 22/tcp
sudo ufw allow ${POSTGRES_PORT}/tcp
sudo ufw allow ${REDIS_PORT}/tcp
sudo ufw allow ${WEAVIATE_PORT}/tcp
EOF

    if [ "$INSTALL_MONITORING" = true ]; then
        cat >> /opt/dify-server/connection-info.txt << EOF
sudo ufw allow ${PROMETHEUS_PORT}/tcp
sudo ufw allow ${GRAFANA_PORT}/tcp
sudo ufw allow ${NODE_EXPORTER_PORT}/tcp
sudo ufw allow ${POSTGRES_EXPORTER_PORT}/tcp
sudo ufw allow ${REDIS_EXPORTER_PORT}/tcp
EOF
    fi

    cat >> /opt/dify-server/connection-info.txt << EOF
sudo ufw enable

=== 使用说明 ===
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}
WEAVIATE_API_KEY=${WEAVIATE_API_KEY}
EOF

    if [ "$INSTALL_MONITORING" = true ]; then
        cat >> /opt/dify-server/connection-info.txt << EOF
GRAFANA_PASSWORD=${GRAFANA_PASSWORD}
EOF
    fi

    # 设置文件权限
    chmod 600 /opt/dify-server/connection-info.txt
    
    log_success "连接信息文件创建完成"
}

# 创建系统服务
create_systemd_service() {
    log_info "创建系统服务..."
    
    # 创建systemd服务文件
    sudo tee /etc/systemd/system/dify-server.service > /dev/null << EOF
[Unit]
Description=Dify Server Services
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/dify-server start
ExecStop=/usr/local/bin/dify-server stop
TimeoutStartSec=300
TimeoutStopSec=120
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF
    
    # 重新加载systemd配置
    sudo systemctl daemon-reload
    
    # 启用服务
    sudo systemctl enable dify-server.service
    
    log_success "系统服务创建完成"
}

# 显示端口列表和防火墙配置提示
show_firewall_configuration() {
    echo ""
    echo "🔥 防火墙配置提示"
    echo ""
    echo "请确保以下端口在防火墙中开放:"
    echo "- SSH: 22"
    echo "- PostgreSQL: ${POSTGRES_PORT}"
    echo "- Redis: ${REDIS_PORT}"
    echo "- Weaviate: ${WEAVIATE_PORT}"
    
    if [ "$INSTALL_MONITORING" = true ]; then
        echo "- Prometheus: ${PROMETHEUS_PORT}"
        echo "- Grafana: ${GRAFANA_PORT}"
        echo "- Node Exporter: ${NODE_EXPORTER_PORT}"
        echo "- PostgreSQL Exporter: ${POSTGRES_EXPORTER_PORT}"
        echo "- Redis Exporter: ${REDIS_EXPORTER_PORT}"
    fi
    
    echo ""
    echo "UFW防火墙配置命令:"
    echo "sudo ufw allow 22/tcp"
    echo "sudo ufw allow ${POSTGRES_PORT}/tcp"
    echo "sudo ufw allow ${REDIS_PORT}/tcp"
    echo "sudo ufw allow ${WEAVIATE_PORT}/tcp"
    
    if [ "$INSTALL_MONITORING" = true ]; then
        echo "sudo ufw allow ${PROMETHEUS_PORT}/tcp"
        echo "sudo ufw allow ${GRAFANA_PORT}/tcp"
        echo "sudo ufw allow ${NODE_EXPORTER_PORT}/tcp"
        echo "sudo ufw allow ${POSTGRES_EXPORTER_PORT}/tcp"
        echo "sudo ufw allow ${REDIS_EXPORTER_PORT}/tcp"
    fi
    
    echo "sudo ufw enable"
    echo ""
}

# 最终检查和总结
final_check_and_summary() {
    log_info "执行最终检查..."
    
    # 等待所有服务完全启动
    sleep 30
    
    # 执行健康检查
    if /usr/local/bin/dify-server health; then
        log_success "所有服务健康检查通过"
    else
        log_warning "部分服务可能尚未完全启动，请稍后再次检查"
    fi
    
    echo ""
    echo "🎉 Dify家庭服务器部署完成！"
    echo ""
    echo "=== 部署摘要 ==="
    echo "- 服务器IP: ${SERVER_IP}"
    echo "- PostgreSQL: ✅ 已部署 (端口: ${POSTGRES_PORT})"
    echo "- Redis: ✅ 已部署 (端口: ${REDIS_PORT})"
    echo "- Weaviate: ✅ 已部署 (端口: ${WEAVIATE_PORT})"
    if [ "$INSTALL_MONITORING" = true ]; then
        echo "- 监控系统: ✅ 已部署"
    else
        echo "- 监控系统: ❌ 未部署 (可通过 INSTALL_MONITORING=true 启用)"
    fi
    echo "- 管理脚本: ✅ 已创建"
    echo "- 系统服务: ✅ 已配置"
    echo "- 中国镜像源: $([ "$USE_CHINA_MIRROR" = true ] && echo "✅ 已启用" || echo "❌ 未启用")"
    echo ""
    echo "=== 重要信息 ==="
    echo "📄 连接信息: /opt/dify-server/connection-info.txt"
    echo "🔧 管理命令: dify-server {start|stop|restart|status|info|health|backup}"
    if [ "$INSTALL_MONITORING" = true ]; then
        echo "📊 监控面板: http://${SERVER_IP}:${GRAFANA_PORT} (admin/${GRAFANA_PASSWORD})"
        echo "🔍 Prometheus: http://${SERVER_IP}:${PROMETHEUS_PORT}"
    fi
    echo ""
    echo "=== 下一步操作 ==="
    echo "1. 配置防火墙 (见下方端口列表)"
    echo "2. 查看连接信息: cat /opt/dify-server/connection-info.txt"
    if [ "$INSTALL_MONITORING" = true ]; then
        echo "3. 访问监控面板: http://${SERVER_IP}:${GRAFANA_PORT}"
    fi
    echo "4. 在开发机器上配置连接到此服务器"
    echo "5. 运行健康检查: dify-server health"
    echo "6. 设置定时备份: 添加 crontab 任务"
    
    # 显示防火墙配置
    show_firewall_configuration
    
    echo ""
    log_warning "请妥善保管连接信息文件中的密码！"
    
    # 显示密码信息
    echo ""
    echo "=== 重要密码信息 ==="
    echo "PostgreSQL密码: ${POSTGRES_PASSWORD}"
    echo "Redis密码: ${REDIS_PASSWORD}"
    echo "Weaviate API Key: ${WEAVIATE_API_KEY}"
    if [ "$INSTALL_MONITORING" = true ]; then
        echo "Grafana密码: ${GRAFANA_PASSWORD}"
    fi
    echo ""
    log_warning "请立即保存这些密码信息！"
    
    # 监控系统说明
    if [ "$INSTALL_MONITORING" = true ]; then
        echo ""
        echo "=== 监控系统使用说明 ==="
        echo "✅ 已安装Prometheus + Grafana监控系统"
        echo "📊 Grafana访问: http://${SERVER_IP}:${GRAFANA_PORT}"
        echo "🔐 登录账号: admin / ${GRAFANA_PASSWORD}"
        echo "📈 Prometheus: http://${SERVER_IP}:${PROMETHEUS_PORT}"
        echo ""
        echo "监控功能:"
        echo "- 系统资源监控 (CPU、内存、磁盘)"
        echo "- PostgreSQL数据库监控"
        echo "- Redis缓存监控"
        echo "- 服务健康状态监控"
        echo ""
        echo "如需自定义Dashboard，请访问Grafana控制台"
    else
        echo ""
        echo "=== 监控系统说明 ==="
        echo "❌ 监控系统未安装"
        echo "如需启用监控系统，请运行:"
        echo "INSTALL_MONITORING=true ./home-server-setup-optimized.sh"
        echo ""
        echo "监控系统包含:"
        echo "- Prometheus (指标收集)"
        echo "- Grafana (可视化面板)"
        echo "- Node Exporter (系统指标)"
        echo "- PostgreSQL Exporter (数据库指标)"
        echo "- Redis Exporter (缓存指标)"
    fi
}

# 主函数
main() {
    # 解析命令行参数
    parse_arguments "$@"
    
    echo "开始部署Dify家庭服务器..."
    echo ""
    
    # 显示配置并确认
    show_configuration
    
    detect_server_ip
    check_port_conflicts
    check_requirements
    install_dependencies
    setup_directories
    create_docker_network
    deploy_postgres
    deploy_redis
    deploy_weaviate
    deploy_monitoring
    create_management_scripts
    create_connection_info
    create_systemd_service
    final_check_and_summary
}

# 信号处理
trap 'log_error "脚本被中断"; exit 1' INT TERM

# 执行主函数
main "$@" 