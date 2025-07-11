# Dify 生产环境模块化部署方案

## 生产环境架构设计

### 1. **整体架构图**

```
                    ┌─────────────────┐
                    │   Load Balancer │
                    │    (Nginx)      │
                    └─────────────────┘
                             │
                    ┌─────────────────┐
                    │   Web Cluster   │
                    │   (Next.js)     │
                    └─────────────────┘
                             │
                    ┌─────────────────┐
                    │  API Gateway    │
                    │   (Nginx)       │
                    └─────────────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│  API Cluster    │ │ Worker Cluster  │ │ Support Services│
│   (Flask)       │ │   (Celery)      │ │ (Sandbox/Proxy) │
└─────────────────┘ └─────────────────┘ └─────────────────┘
         │                   │                   │
         └───────────────────┼───────────────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│  PostgreSQL     │ │     Redis       │ │ Vector Database │
│   (Primary)     │ │   (Cluster)     │ │   (Cluster)     │
└─────────────────┘ └─────────────────┘ └─────────────────┘
```

### 2. **模块化部署策略**

#### **部署层级划分**
1. **负载均衡层** - Nginx 反向代理
2. **应用服务层** - Web/API/Worker 集群
3. **数据存储层** - 数据库集群
4. **支撑服务层** - 沙箱/代理/监控
5. **基础设施层** - 网络/存储/日志

## 生产环境部署步骤

### 阶段一：基础设施准备

#### 1. **服务器规划**

**最小化部署 (单机版)**
```bash
# 服务器配置要求
CPU: 8核+
内存: 16GB+
存储: 200GB+ SSD
网络: 100Mbps+

# 服务分布
- Web服务: 1个实例
- API服务: 2个实例
- Worker服务: 2个实例
- 数据库: 本地部署
```

**标准部署 (多机版)**
```bash
# 负载均衡节点 (1台)
CPU: 4核, 内存: 8GB, 存储: 100GB

# Web服务节点 (2台)
CPU: 4核, 内存: 8GB, 存储: 100GB

# API服务节点 (3台)
CPU: 8核, 内存: 16GB, 存储: 200GB

# Worker服务节点 (2台)
CPU: 8核, 内存: 16GB, 存储: 200GB

# 数据库节点 (3台)
CPU: 8核, 内存: 32GB, 存储: 500GB SSD
```

#### 2. **网络规划**

```bash
# 网络分段
- 公网段: 负载均衡器
- 应用段: Web/API服务
- 数据段: 数据库集群
- 管理段: 监控/日志服务

# 端口规划
- 80/443: HTTP/HTTPS (公网)
- 3000: Web服务 (内网)
- 5001: API服务 (内网)
- 5432: PostgreSQL (内网)
- 6379: Redis (内网)
- 8080: Weaviate (内网)
```

### 阶段二：数据存储层部署

#### 1. **PostgreSQL 高可用部署**

**主从复制配置**
```bash
# 主节点配置
cat > /etc/postgresql/15/main/postgresql.conf << 'EOF'
# 基础配置
listen_addresses = '*'
port = 5432
max_connections = 200

# 复制配置
wal_level = replica
max_wal_senders = 3
wal_keep_size = 64MB
archive_mode = on
archive_command = 'cp %p /var/lib/postgresql/15/archive/%f'

# 性能优化
shared_buffers = 4GB
effective_cache_size = 12GB
work_mem = 64MB
maintenance_work_mem = 512MB
EOF

# 从节点配置
cat > /var/lib/postgresql/15/main/recovery.conf << 'EOF'
standby_mode = 'on'
primary_conninfo = 'host=master_ip port=5432 user=replicator'
trigger_file = '/var/lib/postgresql/15/main/trigger_file'
EOF
```

**数据库初始化脚本**
```bash
#!/bin/bash
# postgres-setup.sh

# 创建数据库和用户
sudo -u postgres psql << 'EOF'
CREATE USER dify WITH PASSWORD 'your_secure_password';
CREATE DATABASE dify OWNER dify;
GRANT ALL PRIVILEGES ON DATABASE dify TO dify;

-- 创建复制用户
CREATE USER replicator WITH REPLICATION LOGIN PASSWORD 'replication_password';
EOF

# 配置防火墙
ufw allow 5432/tcp

# 启动服务
systemctl enable postgresql
systemctl start postgresql
```

#### 2. **Redis 集群部署**

**Redis 集群配置**
```bash
# 创建Redis集群配置
mkdir -p /etc/redis/cluster
for port in 7000 7001 7002 7003 7004 7005; do
  cat > /etc/redis/cluster/redis-${port}.conf << EOF
port ${port}
cluster-enabled yes
cluster-config-file nodes-${port}.conf
cluster-node-timeout 5000
appendonly yes
appendfilename "appendonly-${port}.aof"
dbfilename "dump-${port}.rdb"
logfile "/var/log/redis/redis-${port}.log"
daemonize yes
protected-mode no
bind 0.0.0.0
requirepass your_redis_password
masterauth your_redis_password
EOF
done

# 启动Redis集群
for port in 7000 7001 7002 7003 7004 7005; do
  redis-server /etc/redis/cluster/redis-${port}.conf
done

# 创建集群
redis-cli --cluster create \
  node1:7000 node1:7001 \
  node2:7002 node2:7003 \
  node3:7004 node3:7005 \
  --cluster-replicas 1 \
  -a your_redis_password
```

#### 3. **向量数据库部署**

**Weaviate 集群配置**
```yaml
# weaviate-cluster.yml
version: '3.8'
services:
  weaviate-node-1:
    image: semitechnologies/weaviate:1.19.0
    restart: always
    ports:
      - "8080:8080"
    environment:
      CLUSTER_HOSTNAME: 'node1'
      CLUSTER_GOSSIP_BIND_PORT: '7100'
      CLUSTER_DATA_BIND_PORT: '7101'
      CLUSTER_JOIN: 'node2:7100,node3:7100'
      PERSISTENCE_DATA_PATH: '/var/lib/weaviate'
      AUTHENTICATION_APIKEY_ENABLED: 'true'
      AUTHENTICATION_APIKEY_ALLOWED_KEYS: 'your_weaviate_key'
    volumes:
      - weaviate_data_1:/var/lib/weaviate

  weaviate-node-2:
    image: semitechnologies/weaviate:1.19.0
    restart: always
    ports:
      - "8081:8080"
    environment:
      CLUSTER_HOSTNAME: 'node2'
      CLUSTER_GOSSIP_BIND_PORT: '7100'
      CLUSTER_DATA_BIND_PORT: '7101'
      CLUSTER_JOIN: 'node1:7100,node3:7100'
      PERSISTENCE_DATA_PATH: '/var/lib/weaviate'
      AUTHENTICATION_APIKEY_ENABLED: 'true'
      AUTHENTICATION_APIKEY_ALLOWED_KEYS: 'your_weaviate_key'
    volumes:
      - weaviate_data_2:/var/lib/weaviate

volumes:
  weaviate_data_1:
  weaviate_data_2:
```

### 阶段三：应用服务层部署

#### 1. **API服务集群部署**

**Docker Compose 配置**
```yaml
# api-cluster.yml
version: '3.8'
services:
  api-1:
    image: langgenius/dify-api:1.5.1
    container_name: dify-api-1
    restart: unless-stopped
    environment:
      MODE: api
      SERVER_WORKER_AMOUNT: 4
      GUNICORN_TIMEOUT: 300
    env_file:
      - ./config/api/.env
    volumes:
      - ./data/storage:/app/api/storage
      - ./logs/api-1:/app/api/logs
    ports:
      - "5001:5001"
    networks:
      - dify-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5001/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    deploy:
      resources:
        limits:
          cpus: '4.0'
          memory: 8G
        reservations:
          cpus: '2.0'
          memory: 4G

  api-2:
    image: langgenius/dify-api:1.5.1
    container_name: dify-api-2
    restart: unless-stopped
    environment:
      MODE: api
      SERVER_WORKER_AMOUNT: 4
      GUNICORN_TIMEOUT: 300
    env_file:
      - ./config/api/.env
    volumes:
      - ./data/storage:/app/api/storage
      - ./logs/api-2:/app/api/logs
    ports:
      - "5002:5001"
    networks:
      - dify-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5001/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    deploy:
      resources:
        limits:
          cpus: '4.0'
          memory: 8G
        reservations:
          cpus: '2.0'
          memory: 4G

networks:
  dify-network:
    external: true
```

#### 2. **Worker服务集群部署**

**Worker 集群配置**
```yaml
# worker-cluster.yml
version: '3.8'
services:
  worker-dataset:
    image: langgenius/dify-api:1.5.1
    container_name: dify-worker-dataset
    restart: unless-stopped
    environment:
      MODE: worker
      CELERY_QUEUES: dataset
      CELERY_MAX_WORKERS: 4
      CELERY_MIN_WORKERS: 1
    env_file:
      - ./config/api/.env
    volumes:
      - ./data/storage:/app/api/storage
      - ./logs/worker-dataset:/app/api/logs
    networks:
      - dify-network
    depends_on:
      - redis-cluster
    deploy:
      resources:
        limits:
          cpus: '4.0'
          memory: 6G

  worker-generation:
    image: langgenius/dify-api:1.5.1
    container_name: dify-worker-generation
    restart: unless-stopped
    environment:
      MODE: worker
      CELERY_QUEUES: generation
      CELERY_MAX_WORKERS: 2
      CELERY_MIN_WORKERS: 1
    env_file:
      - ./config/api/.env
    volumes:
      - ./data/storage:/app/api/storage
      - ./logs/worker-generation:/app/api/logs
    networks:
      - dify-network
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 4G

  worker-mail:
    image: langgenius/dify-api:1.5.1
    container_name: dify-worker-mail
    restart: unless-stopped
    environment:
      MODE: worker
      CELERY_QUEUES: mail,ops_trace
      CELERY_MAX_WORKERS: 2
      CELERY_MIN_WORKERS: 1
    env_file:
      - ./config/api/.env
    volumes:
      - ./logs/worker-mail:/app/api/logs
    networks:
      - dify-network
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 2G
```

#### 3. **Web服务集群部署**

**Web 集群配置**
```yaml
# web-cluster.yml
version: '3.8'
services:
  web-1:
    image: langgenius/dify-web:1.5.1
    container_name: dify-web-1
    restart: unless-stopped
    environment:
      NEXT_PUBLIC_API_PREFIX: https://your-domain.com/console/api
      NEXT_PUBLIC_PUBLIC_API_PREFIX: https://your-domain.com/api
      PM2_INSTANCES: 4
    ports:
      - "3001:3000"
    networks:
      - dify-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000"]
      interval: 30s
      timeout: 10s
      retries: 3
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 4G

  web-2:
    image: langgenius/dify-web:1.5.1
    container_name: dify-web-2
    restart: unless-stopped
    environment:
      NEXT_PUBLIC_API_PREFIX: https://your-domain.com/console/api
      NEXT_PUBLIC_PUBLIC_API_PREFIX: https://your-domain.com/api
      PM2_INSTANCES: 4
    ports:
      - "3002:3000"
    networks:
      - dify-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000"]
      interval: 30s
      timeout: 10s
      retries: 3
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 4G
```

### 阶段四：负载均衡配置

#### **Nginx 负载均衡配置**

```nginx
# /etc/nginx/sites-available/dify-production
upstream web_backend {
    least_conn;
    server web-node-1:3001 max_fails=3 fail_timeout=30s;
    server web-node-2:3002 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

upstream api_backend {
    least_conn;
    server api-node-1:5001 max_fails=3 fail_timeout=30s;
    server api-node-2:5002 max_fails=3 fail_timeout=30s;
    server api-node-3:5003 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

# HTTP 重定向到 HTTPS
server {
    listen 80;
    server_name your-domain.com;
    return 301 https://$server_name$request_uri;
}

# HTTPS 主配置
server {
    listen 443 ssl http2;
    server_name your-domain.com;
    
    # SSL 配置
    ssl_certificate /etc/ssl/certs/your-domain.crt;
    ssl_certificate_key /etc/ssl/private/your-domain.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    
    # 安全头
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # 压缩配置
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
    
    # 客户端配置
    client_max_body_size 100M;
    client_body_timeout 60s;
    client_header_timeout 60s;
    
    # API 路由
    location /api/ {
        proxy_pass http://api_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
        proxy_connect_timeout 10s;
        
        # 健康检查
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
        proxy_next_upstream_tries 2;
        proxy_next_upstream_timeout 10s;
    }
    
    location /console/api/ {
        proxy_pass http://api_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
        proxy_connect_timeout 10s;
        
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
        proxy_next_upstream_tries 2;
        proxy_next_upstream_timeout 10s;
    }
    
    # Web 前端路由
    location / {
        proxy_pass http://web_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
        proxy_connect_timeout 10s;
        
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
        proxy_next_upstream_tries 2;
        proxy_next_upstream_timeout 10s;
    }
    
    # 静态文件缓存
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header X-Cache-Status "STATIC";
    }
    
    # 健康检查端点
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}

# 日志配置
log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                '$status $body_bytes_sent "$http_referer" '
                '"$http_user_agent" "$http_x_forwarded_for" '
                'rt=$request_time uct="$upstream_connect_time" '
                'uht="$upstream_header_time" urt="$upstream_response_time"';

access_log /var/log/nginx/dify-access.log main;
error_log /var/log/nginx/dify-error.log;
```

### 阶段五：监控和运维

#### 1. **监控系统部署**

**Prometheus + Grafana 配置**
```yaml
# monitoring.yml
version: '3.8'
services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./config/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
      - '--web.enable-lifecycle'
    networks:
      - monitoring

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=your_admin_password
    volumes:
      - grafana_data:/var/lib/grafana
    networks:
      - monitoring

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.ignored-mount-points=^/(sys|proc|dev|host|etc)($$|/)'
    networks:
      - monitoring

volumes:
  prometheus_data:
  grafana_data:

networks:
  monitoring:
    driver: bridge
```

#### 2. **日志收集系统**

**ELK Stack 配置**
```yaml
# logging.yml
version: '3.8'
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.6.0
    container_name: elasticsearch
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=false
      - "ES_JAVA_OPTS=-Xms2g -Xmx2g"
    ports:
      - "9200:9200"
    volumes:
      - elasticsearch_data:/usr/share/elasticsearch/data
    networks:
      - logging

  logstash:
    image: docker.elastic.co/logstash/logstash:8.6.0
    container_name: logstash
    volumes:
      - ./config/logstash.conf:/usr/share/logstash/pipeline/logstash.conf
    ports:
      - "5044:5044"
    depends_on:
      - elasticsearch
    networks:
      - logging

  kibana:
    image: docker.elastic.co/kibana/kibana:8.6.0
    container_name: kibana
    ports:
      - "5601:5601"
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
    depends_on:
      - elasticsearch
    networks:
      - logging

volumes:
  elasticsearch_data:

networks:
  logging:
    driver: bridge
```

### 阶段六：部署自动化

#### 1. **部署脚本**

```bash
#!/bin/bash
# production-deploy.sh

set -e

# 配置变量
DEPLOY_ENV="production"
DOCKER_REGISTRY="your-registry.com"
VERSION="1.5.1"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}🚀 开始 Dify 生产环境部署...${NC}"

# 检查环境
check_environment() {
    echo -e "${YELLOW}检查部署环境...${NC}"
    
    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ Docker 未安装${NC}"
        exit 1
    fi
    
    # 检查 Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        echo -e "${RED}❌ Docker Compose 未安装${NC}"
        exit 1
    fi
    
    # 检查配置文件
    if [ ! -f "./config/api/.env" ]; then
        echo -e "${RED}❌ API 配置文件不存在${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ 环境检查通过${NC}"
}

# 拉取最新镜像
pull_images() {
    echo -e "${YELLOW}拉取最新镜像...${NC}"
    
    docker pull ${DOCKER_REGISTRY}/dify-api:${VERSION}
    docker pull ${DOCKER_REGISTRY}/dify-web:${VERSION}
    docker pull ${DOCKER_REGISTRY}/dify-worker:${VERSION}
    
    echo -e "${GREEN}✅ 镜像拉取完成${NC}"
}

# 部署数据库
deploy_database() {
    echo -e "${YELLOW}部署数据库服务...${NC}"
    
    docker-compose -f database-cluster.yml up -d
    
    # 等待数据库启动
    sleep 30
    
    # 检查数据库健康状态
    docker-compose -f database-cluster.yml ps
    
    echo -e "${GREEN}✅ 数据库部署完成${NC}"
}

# 部署应用服务
deploy_application() {
    echo -e "${YELLOW}部署应用服务...${NC}"
    
    # 部署 API 服务
    docker-compose -f api-cluster.yml up -d
    
    # 部署 Worker 服务
    docker-compose -f worker-cluster.yml up -d
    
    # 部署 Web 服务
    docker-compose -f web-cluster.yml up -d
    
    # 等待服务启动
    sleep 30
    
    echo -e "${GREEN}✅ 应用服务部署完成${NC}"
}

# 部署监控系统
deploy_monitoring() {
    echo -e "${YELLOW}部署监控系统...${NC}"
    
    docker-compose -f monitoring.yml up -d
    docker-compose -f logging.yml up -d
    
    echo -e "${GREEN}✅ 监控系统部署完成${NC}"
}

# 健康检查
health_check() {
    echo -e "${YELLOW}执行健康检查...${NC}"
    
    # 检查 API 服务
    for i in {1..5}; do
        if curl -f http://localhost:5001/health > /dev/null 2>&1; then
            echo -e "${GREEN}✅ API 服务健康${NC}"
            break
        fi
        echo "等待 API 服务启动... ($i/5)"
        sleep 10
    done
    
    # 检查 Web 服务
    for i in {1..5}; do
        if curl -f http://localhost:3001 > /dev/null 2>&1; then
            echo -e "${GREEN}✅ Web 服务健康${NC}"
            break
        fi
        echo "等待 Web 服务启动... ($i/5)"
        sleep 10
    done
    
    echo -e "${GREEN}✅ 健康检查完成${NC}"
}

# 主函数
main() {
    check_environment
    pull_images
    deploy_database
    deploy_application
    deploy_monitoring
    health_check
    
    echo -e "${GREEN}🎉 Dify 生产环境部署完成！${NC}"
    echo -e "${YELLOW}访问地址：${NC}"
    echo "- Web界面: https://your-domain.com"
    echo "- API文档: https://your-domain.com/console/api/docs"
    echo "- 监控面板: http://your-domain.com:3000"
    echo "- 日志查看: http://your-domain.com:5601"
}

# 执行主函数
main "$@"
```

#### 2. **CI/CD 配置**

**GitHub Actions 配置**
```yaml
# .github/workflows/production-deploy.yml
name: Production Deploy

on:
  push:
    branches: [main]
    tags: ['v*']

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v3
      
    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v2
      
    - name: Login to Docker Registry
      uses: docker/login-action@v2
      with:
        registry: ${{ secrets.DOCKER_REGISTRY }}
        username: ${{ secrets.DOCKER_USERNAME }}
        password: ${{ secrets.DOCKER_PASSWORD }}
        
    - name: Build and push API image
      uses: docker/build-push-action@v3
      with:
        context: ./api
        push: true
        tags: ${{ secrets.DOCKER_REGISTRY }}/dify-api:${{ github.sha }}
        
    - name: Build and push Web image
      uses: docker/build-push-action@v3
      with:
        context: ./web
        push: true
        tags: ${{ secrets.DOCKER_REGISTRY }}/dify-web:${{ github.sha }}
        
    - name: Deploy to production
      uses: appleboy/ssh-action@v0.1.5
      with:
        host: ${{ secrets.PRODUCTION_HOST }}
        username: ${{ secrets.PRODUCTION_USER }}
        key: ${{ secrets.PRODUCTION_SSH_KEY }}
        script: |
          cd /opt/dify-production
          export VERSION=${{ github.sha }}
          ./production-deploy.sh
```

## 运维管理

### 1. **备份策略**

```bash
#!/bin/bash
# backup.sh - 数据备份脚本

BACKUP_DIR="/opt/dify-backup"
DATE=$(date +%Y%m%d_%H%M%S)

# 数据库备份
pg_dump -h localhost -U dify -d dify > ${BACKUP_DIR}/database_${DATE}.sql

# 文件存储备份
tar -czf ${BACKUP_DIR}/storage_${DATE}.tar.gz /opt/dify-production/data/storage

# 配置文件备份
tar -czf ${BACKUP_DIR}/config_${DATE}.tar.gz /opt/dify-production/config

# 清理旧备份 (保留30天)
find ${BACKUP_DIR} -name "*.sql" -mtime +30 -delete
find ${BACKUP_DIR} -name "*.tar.gz" -mtime +30 -delete

echo "备份完成: ${DATE}"
```

### 2. **监控告警**

**Prometheus 告警规则**
```yaml
# alerts.yml
groups:
- name: dify-alerts
  rules:
  - alert: HighCPUUsage
    expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High CPU usage detected"
      description: "CPU usage is above 80% for more than 5 minutes"
      
  - alert: HighMemoryUsage
    expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 90
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "High memory usage detected"
      description: "Memory usage is above 90% for more than 5 minutes"
      
  - alert: APIServiceDown
    expr: up{job="dify-api"} == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "API service is down"
      description: "Dify API service is not responding"
```

### 3. **故障恢复**

**自动故障恢复脚本**
```bash
#!/bin/bash
# recovery.sh - 故障恢复脚本

# 检查服务状态
check_service() {
    local service=$1
    local url=$2
    
    if ! curl -f $url > /dev/null 2>&1; then
        echo "服务 $service 异常，尝试重启..."
        docker-compose -f ${service}-cluster.yml restart
        sleep 30
        
        if curl -f $url > /dev/null 2>&1; then
            echo "服务 $service 恢复正常"
        else
            echo "服务 $service 重启失败，需要人工介入"
            # 发送告警通知
            curl -X POST -H 'Content-type: application/json' \
                --data '{"text":"Dify '$service' 服务故障，需要人工处理"}' \
                $SLACK_WEBHOOK_URL
        fi
    fi
}

# 检查各个服务
check_service "api" "http://localhost:5001/health"
check_service "web" "http://localhost:3001"

# 检查数据库连接
if ! pg_isready -h localhost -p 5432 -U dify; then
    echo "数据库连接异常"
    # 尝试重启数据库
    systemctl restart postgresql
fi

# 检查Redis连接
if ! redis-cli -h localhost -p 6379 ping; then
    echo "Redis连接异常"
    # 尝试重启Redis
    systemctl restart redis
fi
```

## 总结

这个完整的生产环境部署方案提供了：

1. **模块化架构** - 每个组件可以独立部署和扩展
2. **高可用性** - 数据库集群、应用集群、负载均衡
3. **可扩展性** - 支持水平扩展和垂直扩展
4. **监控运维** - 完整的监控、日志、告警系统
5. **自动化部署** - CI/CD流水线和自动化脚本
6. **故障恢复** - 自动故障检测和恢复机制

通过这个方案，您可以实现：
- 开发环境的快速搭建和热更新
- 生产环境的稳定部署和高可用
- 各个模块的独立管理和配置
- 完整的监控和运维体系

建议按照阶段逐步实施，先在测试环境验证，再部署到生产环境。 

## 🏠 家庭服务器配置 (基础服务层)

**家庭服务器部署脚本内容**：

```bash
#!/bin/bash
# 家庭服务器基础服务部署脚本

# 部署内容：
# - PostgreSQL 数据库
# - Redis 缓存  
# - Weaviate 向量数据库
# - Prometheus + Grafana 监控
# - 统一管理脚本

# 优势：
# ✅ 24x7稳定运行
# ✅ 为所有开发机器提供基础服务
# ✅ 完整的监控和备份
# ✅ 网络隔离和安全配置
```

## 💻 Hyper-V Ubuntu 配置 (后端开发层)

**后端开发环境配置**：

```bash
#!/bin/bash
# Hyper-V Ubuntu 后端开发环境配置

# 连接到家庭服务器的数据库
export DB_HOST="192.168.1.100"  # 家庭服务器IP
export DB_PASSWORD="dify_dev_2024"
export REDIS_HOST="192.168.1.100"
export WEAVIATE_ENDPOINT="http://192.168.1.100:8080"

# 本地开发服务
# - API服务 (Flask debug模式)
# - Worker服务 (Celery调试)
# - 开发工具 (VS Code, 调试器)
# - 数据库客户端工具
```

## 🖥️ Windows 本地配置 (前端开发层)

**Windows前端开发配置**：

```powershell
# Windows 前端开发环境
# 环境变量配置

$env:NEXT_PUBLIC_API_PREFIX = "http://192.168.1.101:5001/console/api"  # Hyper-V Ubuntu IP
$env:NEXT_PUBLIC_PUBLIC_API_PREFIX = "http://192.168.1.101:5001/api"

# 本地服务
# - Next.js 开发服务器
# - VS Code 前端开发
# - 浏览器实时测试
# - 前端构建工具
```

## 🌐 网络连接示意图

```
家庭网络 (192.168.1.x)
│
├── 🏠 家庭服务器 (192.168.1.100)
│   ├── PostgreSQL :5432
│   ├── Redis :6379  
│   ├── Weaviate :8080
│   └── Grafana :3000
│
├── 💻 Hyper-V Ubuntu (192.168.1.101)
│   ├── API服务 :5001
│   ├── Worker服务
│   └── 开发工具
│
└── 🖥️ Windows本地 (192.168.1.102)
    ├── Web服务 :3000
    ├── VS Code
    └── 浏览器测试
```

## 📋 部署步骤

### **步骤1: 部署家庭服务器**
```bash
# 在家庭服务器上运行
wget https://raw.githubusercontent.com/your-repo/home-server-setup.sh
chmod +x home-server-setup.sh
./home-server-setup.sh

# 完成后会显示连接信息
dify-server info
```

### **步骤2: 配置Hyper-V Ubuntu**
```bash
# 克隆项目
git clone https://github.com/langgenius/dify.git
cd dify

# 配置连接到家庭服务器
export DB_HOST="192.168.1.100"  # 替换为实际IP
export REDIS_HOST="192.168.1.100"

# 安装后端开发环境
cd api
pip install uv
uv sync --dev

# 配置环境变量
cp .env.example .env
# 编辑.env文件，设置数据库连接信息

# 启动后端服务
uv run flask run --host 0.0.0.0 --port 5001 --debug
```

### **步骤3: 配置Windows前端**
```powershell
# 克隆项目（如果还没有）
git clone https://github.com/langgenius/dify.git
cd dify\web

# 安装Node.js和pnpm
npm install -g pnpm

# 安装依赖
pnpm install

# 配置环境变量
Copy-Item .env.example .env.local
# 编辑.env.local文件

# 启动前端开发服务
pnpm dev
```

## 🔧 各机器的具体职责

### **家庭服务器职责**
- ✅ 提供稳定的数据库服务
- ✅ 缓存和向量数据库
- ✅ 监控所有服务状态  
- ✅ 数据备份和恢复
- ✅ 网络安全和访问控制

### **Hyper-V Ubuntu职责**
- ✅ 后端代码开发和调试
- ✅ API接口测试
- ✅ Worker任务调试
- ✅ 数据库管理操作
- ✅ 后端单元测试

### **Windows本地职责**
- ✅ 前端界面开发
- ✅ 用户体验测试
- ✅ 前端组件调试
- ✅ 浏览器兼容性测试
- ✅ 前端构建和优化

## 🚀 开发工作流

### **日常开发流程**
1. **启动基础服务**: 家庭服务器自动运行
2. **后端开发**: 在Hyper-V Ubuntu上修改API代码
3. **前端开发**: 在Windows上修改Web代码
4. **实时测试**: 前端连接后端API进行测试
5. **数据查看**: 通过图形界面工具查看数据库

### **调试流程**
1. **数据库调试**: 在Hyper-V Ubuntu上使用pgAdmin
2. **API调试**: Flask debug模式，实时重载
3. **前端调试**: Next.js dev模式，热更新
4. **跨服务调试**: 通过监控面板查看服务状态

## 💡 这种配置的优势

### **性能优势**
- 🚀 **基础服务稳定**: 数据库24x7运行，不受开发影响
- 🔄 **开发热更新**: 前后端都支持实时重载
- 📊 **监控可视**: 实时查看所有服务状态

### **开发体验优势**
- 🛠️ **工具齐全**: 图形界面便于调试和数据查看
- 🔧 **环境隔离**: 各层服务独立，互不影响
- 🎯 **职责明确**: 每台机器专注特定开发任务

### **运维优势**
- 📈 **易于扩展**: 可以随时添加更多开发机器
- 🔒 **安全可控**: 网络访问权限清晰
- 💾 **数据安全**: 集中备份，不易丢失

这种配置完美契合您的需求：既能实时查看后台数据，又能进行前端开发，还保持了各组件的独立性。您觉得这个方案如何？需要我为任何特定的机器提供更详细的配置脚本吗？ 