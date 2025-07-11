# Dify 家庭服务器部署使用指南

## 📋 项目简介

基于Docker的Dify家庭服务器部署方案，包含PostgreSQL、Redis、Weaviate三个核心服务。

**项目结构：**
```
dify-server/
├── docker-setup-updated.sh     # 主管理脚本
├── docker-compose.yml          # 服务配置
├── dify.env                    # 环境变量
├── redis.conf                 # Redis配置
├── init-scripts/              # 初始化脚本
├── backups/                   # 备份目录
└── logs/                      # 日志目录
```

---

## 🚀 快速开始

### 1. 初始化部署
```bash
./docker-setup-updated.sh setup
```
**作用：** 检查环境、配置IP、同步密码、拉取镜像
**案例：** 首次部署或重新配置时使用

### 2. 启动服务
```bash
./docker-setup-updated.sh start
```
**作用：** 启动所有容器并显示状态
**案例：** 开机后启动服务或维护后重启

### 3. 查看状态
```bash
./docker-setup-updated.sh status
```
**作用：** 显示容器状态和健康检查结果
**案例：** 日常检查服务是否正常运行

---

## 🔧 管理命令

### 服务控制
```bash
# 停止服务
./docker-setup-updated.sh stop

# 重启服务
./docker-setup-updated.sh restart

# 健康检查
./docker-setup-updated.sh health
```

### 日志查看
```bash
# 查看所有日志
./docker-setup-updated.sh logs

# 查看特定服务日志
./docker-setup-updated.sh logs postgres
./docker-setup-updated.sh logs redis
./docker-setup-updated.sh logs weaviate
```

### 配置管理
```bash
# 同步密码配置
./docker-setup-updated.sh sync

# 显示连接信息
./docker-setup-updated.sh info
```

### 数据管理
```bash
# 备份数据
./docker-setup-updated.sh backup

# 清理数据（危险操作）
./docker-setup-updated.sh clean
```

---

## 📝 配置文件

### dify.env - 环境配置
```env
# 端口配置
POSTGRES_PORT=5432
REDIS_PORT=6379
WEAVIATE_PORT=8080

# 数据库配置
POSTGRES_PASSWORD=your_secure_password
REDIS_PASSWORD=your_redis_password
WEAVIATE_API_KEY=your_weaviate_key

# 服务器IP（自动检测）
SERVER_IP=192.168.1.100
```

### redis.conf - Redis配置
```conf
# 密码认证（必须与dify.env中一致）
requirepass your_redis_password

# 内存限制
maxmemory 1gb
maxmemory-policy allkeys-lru

# 数据持久化
appendonly yes
save 900 1
```

---

## 🗄️ 数据库操作

### PostgreSQL
```bash
# 连接数据库
docker exec -it dify-postgres psql -U dify -d dify

# 常用SQL命令
SELECT version();           # 查看版本
\dt                        # 查看表
\d table_name              # 查看表结构
SELECT * FROM users;       # 查询数据

# 备份恢复
docker exec -t dify-postgres pg_dump -U dify dify > backup.sql
cat backup.sql | docker exec -i dify-postgres psql -U dify -d dify
```

### Redis
```bash
# 连接Redis
docker exec -it dify-redis redis-cli -a your_password

# 常用命令
SET key "value"            # 设置键值
GET key                    # 获取值
DEL key                    # 删除键
INFO                       # 查看信息
MONITOR                    # 监控命令
```

### Weaviate
```bash
# 检查状态
curl -H "Authorization: Bearer your_api_key" \
     http://192.168.1.100:8080/v1/.well-known/ready

# 查看元数据
curl -H "Authorization: Bearer your_api_key" \
     http://192.168.1.100:8080/v1/meta
```

---

## 💾 数据持久化

### 数据卷管理
```bash
# 查看数据卷
docker volume ls

# 查看详细信息
docker volume inspect docker_db_postgres_data
docker volume inspect docker_db_redis_data
docker volume inspect docker_db_weaviate_data

# 查看大小
docker system df -v
```

### 备份策略
```bash
# 自动备份（每天凌晨2点）
echo "0 2 * * * cd $(pwd) && ./docker-setup-updated.sh backup" | crontab -

# 手动备份
./docker-setup-updated.sh backup

# 查看备份
ls -la backups/
```

### 数据恢复
```bash
# 停止服务
./docker-setup-updated.sh stop

# 清理数据（可选）
docker volume rm docker_db_postgres_data docker_db_redis_data docker_db_weaviate_data

# 启动服务
./docker-setup-updated.sh start

# 恢复PostgreSQL
cat backups/20241219_143022/postgres_backup.sql | docker exec -i dify-postgres psql -U dify -d dify

# 恢复Redis
docker cp backups/20241219_143022/redis_backup.rdb dify-redis:/data/dump.rdb
docker restart dify-redis

# 恢复Weaviate
docker run --rm -v docker_db_weaviate_data:/data -v $(pwd)/backups/20241219_143022:/backup alpine tar xzf /backup/weaviate_backup.tar.gz -C /data
```

---

## 🚨 故障排除

### 常见问题

#### Redis连接失败
```bash
# 检查密码同步
./docker-setup-updated.sh info

# 同步密码
./docker-setup-updated.sh sync

# 重启Redis
docker restart dify-redis
```

#### PostgreSQL连接超时
```bash
# 查看日志
./docker-setup-updated.sh logs postgres

# 检查进程
docker exec -it dify-postgres pg_isready -U dify -d dify

# 重启服务
docker restart dify-postgres
```

#### 端口冲突
```bash
# 查看端口占用
netstat -tlnp | grep 5432

# 修改端口（编辑dify.env）
vim dify.env

# 重启服务
./docker-setup-updated.sh restart
```

### 权限问题
```bash
# 修复文件权限
chmod 644 dify.env redis.conf
chmod +x docker-setup-updated.sh

# 修复目录权限
sudo chown -R $USER:$USER ~/dify-server
```

---

## 🔧 高级配置

### 性能优化
```bash
# PostgreSQL优化（编辑docker-compose.yml）
-c shared_buffers=512MB
-c effective_cache_size=2GB
-c work_mem=8MB

# Redis优化（编辑redis.conf）
maxmemory 2gb
tcp-keepalive 60
timeout 300
```

### 安全配置
```bash
# 防火墙配置
sudo ufw allow from 192.168.1.0/24 to any port 5432
sudo ufw allow from 192.168.1.0/24 to any port 6379
sudo ufw allow from 192.168.1.0/24 to any port 8080

# 生成强密码
openssl rand -base64 32
```

### 监控脚本
```bash
#!/bin/bash
# health-check.sh
while true; do
    if ./docker-setup-updated.sh health > /dev/null 2>&1; then
        echo "$(date): ✅ 服务正常"
    else
        echo "$(date): ❌ 服务异常"
        # 发送告警
    fi
    sleep 300
done
```

---

## 📊 维护任务

### 日常维护
```bash
# 每日检查
./docker-setup-updated.sh health
./docker-setup-updated.sh status

# 每周清理
docker system prune -f
docker image prune -f

# 每月备份
./docker-setup-updated.sh backup
```

### 系统监控
```bash
# 资源使用
docker stats --no-stream
df -h
free -h

# 日志大小
du -sh logs/

# 清理旧日志
find logs/ -name "*.log" -mtime +30 -delete
```

---

## 🎯 连接信息

部署完成后，使用以下信息连接服务：

```bash
# 查看连接信息
./docker-setup-updated.sh info
```

**PostgreSQL连接：**
- 地址：`192.168.1.100:5432`
- 用户：`dify`
- 数据库：`dify`
- 连接串：`postgresql://dify:password@192.168.1.100:5432/dify`

**Redis连接：**
- 地址：`192.168.1.100:6379`
- 连接串：`redis://:password@192.168.1.100:6379`

**Weaviate连接：**
- 地址：`http://192.168.1.100:8080`
- API Key：`your_api_key`

---

## ✅ 部署检查清单

- [ ] Docker环境安装完成
- [ ] 配置文件创建完成
- [ ] 服务初始化成功
- [ ] 健康检查通过
- [ ] 防火墙配置正确
- [ ] 备份功能测试通过
- [ ] 连接信息记录完成

**完成部署！** 🎉

现在您可以在其他机器上使用这些连接信息来连接Dify服务器了。 