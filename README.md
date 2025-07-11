# Dify 家庭服务器 Docker 部署方案

这是一个基于Docker的Dify家庭服务器部署方案，包含PostgreSQL、Redis和Weaviate三个核心服务。

## 📦 方案特点

- ✅ **纯Docker方案**: 无需系统级配置，只需Docker环境
- ✅ **一键部署**: 简单的脚本操作，自动化程度高
- ✅ **配置灵活**: 支持自定义端口、密码等配置
- ✅ **数据持久化**: 使用Docker卷保证数据安全
- ✅ **完整备份**: 支持数据库、配置文件完整备份
- ✅ **健康检查**: 内置服务健康监控
- ✅ **安全加固**: 密码保护、网络隔离

## 🏗️ 架构组成

```
┌─────────────────────────────────────────┐
│            Dify 家庭服务器               │
├─────────────────────────────────────────┤
│  PostgreSQL (5432)  │  Redis (6379)     │
│  ├─ 数据库存储      │  ├─ 缓存服务      │
│  ├─ 用户数据        │  ├─ 会话管理      │
│  └─ 应用配置        │  └─ 任务队列      │
├─────────────────────┼───────────────────┤
│  Weaviate (8080)    │  Docker Network   │
│  ├─ 向量数据库      │  ├─ 服务通信      │
│  ├─ 语义搜索        │  ├─ 数据隔离      │
│  └─ RAG支持         │  └─ 安全控制      │
└─────────────────────────────────────────┘
```

## 🚀 快速开始

### 1. 前置要求

- Ubuntu 18.04+ 或其他Linux发行版
- Docker 20.10+ 
- Docker Compose V2
- 4GB+ 内存 (推荐8GB)
- 20GB+ 可用磁盘空间

### 2. 下载部署文件

```bash
# 创建项目目录
mkdir dify-server && cd dify-server

# 下载所有必要文件 (这里假设您已经有了文件)
# docker-compose.yml
# docker-setup.sh
# dify.env
# redis.conf
# init-scripts/01-init.sql
```

### 3. 初始化部署

```bash
# 添加执行权限
chmod +x docker-setup.sh

# 初始化部署 (会自动检测IP、生成密码)
./docker-setup.sh setup
```

### 4. 启动服务

```bash
# 启动所有服务
./docker-setup.sh start

# 查看服务状态
./docker-setup.sh status
```

### 5. 查看连接信息

```bash
# 显示连接信息和密码
./docker-setup.sh info
```

## 🔧 管理命令

```bash
# 基础操作
./docker-setup.sh setup     # 初始化部署
./docker-setup.sh start     # 启动服务
./docker-setup.sh stop      # 停止服务
./docker-setup.sh restart   # 重启服务
./docker-setup.sh status    # 查看状态

# 监控和日志
./docker-setup.sh health    # 健康检查
./docker-setup.sh logs      # 查看所有日志
./docker-setup.sh logs postgres  # 查看PostgreSQL日志
./docker-setup.sh logs redis     # 查看Redis日志
./docker-setup.sh logs weaviate  # 查看Weaviate日志

# 数据管理
./docker-setup.sh backup    # 备份数据
./docker-setup.sh clean     # 清理数据 (危险操作)
./docker-setup.sh info      # 显示连接信息
```

## ⚙️ 配置说明

### 环境变量配置 (dify.env)

```env
# 端口配置
POSTGRES_PORT=5432
REDIS_PORT=6379
WEAVIATE_PORT=8080

# 数据库配置
POSTGRES_DB=dify
POSTGRES_USER=dify
POSTGRES_PASSWORD=your_password

# Redis配置
REDIS_PASSWORD=your_redis_password

# Weaviate配置
WEAVIATE_API_KEY=your_api_key

# 服务器IP (自动检测)
SERVER_IP=192.168.1.100
```

### 自定义端口

如需修改端口，编辑 `dify.env` 文件：

```bash
# 修改端口
POSTGRES_PORT=15432
REDIS_PORT=16379
WEAVIATE_PORT=18080

# 重启服务使配置生效
./docker-setup.sh restart
```

## 🔒 安全配置

### 1. 防火墙设置

```bash
# 开放必要端口
sudo ufw allow 22/tcp      # SSH
sudo ufw allow 5432/tcp    # PostgreSQL
sudo ufw allow 6379/tcp    # Redis
sudo ufw allow 8080/tcp    # Weaviate
sudo ufw enable
```

### 2. 密码安全

- 脚本会自动生成强密码
- 密码存储在 `dify.env` 文件中
- 建议定期更换密码

### 3. 网络安全

- 服务运行在独立Docker网络中
- 只暴露必要的端口
- 支持IP绑定限制访问

## 💾 数据备份

### 自动备份

```bash
# 执行完整备份
./docker-setup.sh backup

# 备份内容包括:
# - PostgreSQL数据库 (.sql)
# - Redis数据 (.rdb)
# - Weaviate向量数据 (.tar.gz)
# - 配置文件 (.tar.gz)
```

### 备份策略

- 备份文件保存在 `backups/` 目录
- 自动清理7天前的备份
- 建议设置定时备份任务

```bash
# 添加到crontab (每天凌晨2点备份)
0 2 * * * cd /path/to/dify-server && ./docker-setup.sh backup
```

## 🔍 故障排除

### 常见问题

1. **服务启动失败**
   ```bash
   # 检查日志
   ./docker-setup.sh logs
   
   # 检查端口占用
   sudo netstat -tulpn | grep :5432
   ```

2. **连接被拒绝**
   ```bash
   # 检查防火墙
   sudo ufw status
   
   # 检查服务状态
   ./docker-setup.sh health
   ```

3. **数据丢失**
   ```bash
   # 检查数据卷
   docker volume ls | grep dify
   
   # 恢复备份
   # (需要手动操作，参考备份文件)
   ```

### 健康检查

```bash
# 执行健康检查
./docker-setup.sh health

# 输出示例:
# ✅ PostgreSQL: 健康
# ✅ Redis: 健康  
# ✅ Weaviate: 健康
```

## 📊 性能优化

### 资源配置

- **PostgreSQL**: 已优化连接数、缓存等参数
- **Redis**: 配置内存限制和淘汰策略
- **Weaviate**: 适合中小规模向量存储

### 监控建议

虽然本方案不包含监控系统，但您可以：

1. 使用 `docker stats` 查看资源使用
2. 定期执行健康检查
3. 监控备份任务执行情况
4. 关注日志异常信息

## 🌐 开发环境连接

### 连接字符串示例

```bash
# PostgreSQL
postgresql://dify:your_password@192.168.1.100:5432/dify

# Redis  
redis://:your_redis_password@192.168.1.100:6379

# Weaviate
http://192.168.1.100:8080
API-Key: your_api_key
```

### 在其他机器上使用

1. 确保网络可达
2. 配置防火墙规则
3. 使用正确的IP和密码
4. 测试连接可用性

## 📋 文件结构

```
dify-server/
├── docker-compose.yml      # Docker Compose配置
├── docker-setup.sh         # 管理脚本
├── dify.env               # 环境变量
├── redis.conf             # Redis配置
├── init-scripts/          # 数据库初始化脚本
│   └── 01-init.sql
├── backups/               # 备份目录
├── logs/                  # 日志目录 (可选)
└── README.md              # 说明文档
```

## 🆚 与传统部署对比

| 特性 | Docker方案 | 传统脚本方案 |
|------|------------|--------------|
| 部署复杂度 | ⭐⭐ | ⭐⭐⭐⭐ |
| 系统依赖 | 仅需Docker | 需要多个系统包 |
| 配置管理 | 集中化 | 分散在系统中 |
| 数据隔离 | 完全隔离 | 系统级混合 |
| 迁移便利性 | 非常容易 | 较复杂 |
| 资源占用 | 稍高 | 较低 |
| 维护难度 | 简单 | 中等 |

## 🎯 适用场景

✅ **适合的场景:**
- 家庭/小团队开发环境
- 快速原型验证
- 学习和测试用途
- 需要快速部署的场景
- 多环境部署需求

❌ **不适合的场景:**
- 大规模生产环境
- 需要复杂监控的场景
- 对性能要求极高的应用
- 需要与现有系统深度集成

---

## 📞 支持

如有问题，请检查：
1. Docker和Docker Compose版本
2. 系统资源是否充足
3. 网络和防火墙配置
4. 日志错误信息

这个Docker方案提供了一个简洁、可靠的Dify家庭服务器部署选择！
