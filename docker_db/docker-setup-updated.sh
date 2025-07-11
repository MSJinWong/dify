#!/bin/bash

# Dify 家庭服务器 Docker 部署脚本 (简化版)
# 版本: 1.2.0
# 日期: 2024-12-19
# 更新: 简化配置，统一使用环境变量

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
Dify 家庭服务器 Docker 部署脚本 (简化版)

用法: $0 [命令] [选项]

命令:
  start     启动所有服务
  stop      停止所有服务
  restart   重启所有服务
  status    查看服务状态
  logs      查看服务日志
  backup    备份数据
  clean     清理数据 (危险操作)
  setup     初始化部署
  health    健康检查
  detailed  详细系统检测
  info      显示连接信息

选项:
  --help    显示此帮助信息

示例:
  $0 setup          # 初始化部署
  $0 start          # 启动所有服务
  $0 logs postgres  # 查看PostgreSQL日志
  $0 backup         # 备份数据
  $0 health         # 执行健康检查
  $0 detailed       # 详细系统检测

注意:
  所有配置都在 dify.env 文件中，统一管理

EOF
}

# 检查依赖
check_dependencies() {
    log_info "检查系统依赖..."
    
    # 检查Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi
    
    # 检查Docker Compose
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose 未安装或版本过低"
        exit 1
    fi
    
    log_success "依赖检查通过"
}

# 检查配置文件
check_config_files() {
    log_info "检查配置文件..."
    
    if [ ! -f "dify.env" ]; then
        log_error "环境配置文件 dify.env 不存在"
        log_info "请确保 dify.env 文件存在并包含必要的配置"
        exit 1
    fi
    
    if [ ! -f "docker-compose.yml" ]; then
        log_error "Docker Compose 配置文件不存在"
        exit 1
    fi
    
    log_success "配置文件检查通过"
}

# 检测服务器IP
detect_server_ip() {
    local server_ip=""
    
    # 尝试多种方法获取IP
    if command -v hostname &> /dev/null; then
        server_ip=$(hostname -I | awk '{print $1}')
    fi
    
    if [ -z "$server_ip" ]; then
        server_ip=$(ip route get 1 | awk '{print $7; exit}' 2>/dev/null || true)
    fi
    
    if [ -z "$server_ip" ]; then
        server_ip=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d'/' -f1)
    fi
    
    if [ -z "$server_ip" ]; then
        log_warning "无法自动检测服务器IP"
        read -p "请输入服务器IP地址: " server_ip
    fi
    
    echo "$server_ip"
}

# 更新环境配置
update_env_config() {
    local server_ip="$1"
    log_info "更新环境配置..."
    
    # 更新 dify.env 文件中的服务器IP
    if [ -f "dify.env" ]; then
        # 使用临时文件避免权限问题
        cp dify.env dify.env.tmp
        sed "s/SERVER_IP=YOUR_SERVER_IP/SERVER_IP=${server_ip}/g" dify.env.tmp > dify.env
        rm dify.env.tmp
        log_success "环境配置已更新: ${server_ip}"
    else
        log_warning "环境配置文件 dify.env 不存在"
    fi
}

# 验证配置
validate_config() {
    log_info "验证配置..."
    
    # 检查必要的环境变量
    local required_vars=("POSTGRES_PASSWORD" "REDIS_PASSWORD" "WEAVIATE_API_KEY")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}=" dify.env; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_error "缺少必要的环境变量: ${missing_vars[*]}"
        log_info "请在 dify.env 文件中添加这些配置"
        exit 1
    fi
    
    log_success "配置验证通过"
}

# 显示配置摘要
show_config_summary() {
    echo ""
    echo "=== 配置摘要 ==="
    echo "PostgreSQL密码: $(grep "POSTGRES_PASSWORD=" dify.env | cut -d'=' -f2)"
    echo "Redis密码: $(grep "REDIS_PASSWORD=" dify.env | cut -d'=' -f2)"
    echo "Redis内存限制: $(grep "REDIS_MAXMEMORY=" dify.env | cut -d'=' -f2)"
    echo "Weaviate API Key: $(grep "WEAVIATE_API_KEY=" dify.env | cut -d'=' -f2)"
    echo "服务器IP: $(grep "SERVER_IP=" dify.env | cut -d'=' -f2)"
    echo ""
}

# 初始化部署
setup_deployment() {
    log_info "初始化 Dify 家庭服务器部署..."
    
    check_dependencies
    check_config_files
    validate_config
    
    # 检测服务器IP
    local server_ip=$(detect_server_ip)
    update_env_config "$server_ip"
    
    # 显示配置摘要
    show_config_summary
    
    # 创建必要的目录
    mkdir -p init-scripts backups logs
    
    # 拉取镜像
    log_info "拉取Docker镜像..."
    docker compose --env-file dify.env pull
    
    log_success "初始化完成！"
    log_info "运行 '$0 start' 启动服务"
}

# 启动服务
start_services() {
    log_info "启动 Dify 服务..."
    
    check_config_files
    validate_config
    
    docker compose --env-file dify.env up -d
    
    log_success "服务启动完成"
    
    # 等待服务启动
    log_info "等待服务启动..."
    sleep 15
    
    # 显示服务状态
    show_status
}

# 停止服务
stop_services() {
    log_info "停止 Dify 服务..."
    docker compose --env-file dify.env down
    log_success "服务已停止"
}

# 重启服务
restart_services() {
    log_info "重启 Dify 服务..."
    stop_services
    sleep 5
    start_services
}

# 查看服务状态
show_status() {
    echo ""
    echo "=== Dify 服务器状态 ==="
    echo ""
    echo "Docker 容器状态:"
    docker compose --env-file dify.env ps
    echo ""
    echo "服务健康状态:"
    
    # 检查PostgreSQL
    local postgres_cmd="docker compose --env-file dify.env exec -T postgres pg_isready -U dify -d dify"
    echo "🔍 检测PostgreSQL: $postgres_cmd"
    if $postgres_cmd > /dev/null 2>&1; then
        echo "✅ PostgreSQL: 健康"
    else
        echo "❌ PostgreSQL: 异常"
        echo "   错误输出: $($postgres_cmd 2>&1)"
    fi
    
    # 检查Redis
    local redis_password=$(grep "REDIS_PASSWORD=" dify.env | cut -d'=' -f2 | tr -d '\r\n\t ' | tr -d "'\"")
    echo "🔍 检测Redis: docker exec dify-redis redis-cli -a [密码已隐藏] ping"
    echo "   从配置文件读取的密码: '$redis_password'"
    echo "   密码长度: ${#redis_password} 字符"
    local redis_result=$(docker exec dify-redis redis-cli -a "$redis_password" ping 2>&1)
    if echo "$redis_result" | grep -q "PONG"; then
        echo "✅ Redis: 健康 (返回: PONG)"
    else
        echo "❌ Redis: 异常"
        echo "   实际返回: $redis_result"
        echo "   调试: 原始grep结果: '$(grep "REDIS_PASSWORD=" dify.env)'"
    fi
    
    # 检查Weaviate
    local weaviate_port=$(grep "WEAVIATE_PORT=" dify.env | cut -d'=' -f2)
    local weaviate_url="http://127.0.0.1:${weaviate_port}/v1/.well-known/ready"
    local weaviate_cmd="curl -s -f $weaviate_url"
    echo "🔍 检测Weaviate: $weaviate_cmd"
    local weaviate_result=$($weaviate_cmd 2>&1)
    local weaviate_exit_code=$?
    if [ $weaviate_exit_code -eq 0 ]; then
        echo "✅ Weaviate: 健康 (HTTP 200)"
    else
        echo "❌ Weaviate: 异常"
        echo "   退出码: $weaviate_exit_code"
        echo "   错误输出: $weaviate_result"
        # 尝试获取更多信息
        local weaviate_status=$(curl -s -w "%{http_code}" -o /dev/null $weaviate_url 2>/dev/null || echo "连接失败")
        echo "   HTTP状态码: $weaviate_status"
    fi
    
    echo ""
}

# 查看服务日志
show_logs() {
    local service="$1"
    
    if [ -z "$service" ]; then
        log_info "显示所有服务日志..."
        docker compose --env-file dify.env logs -f
    else
        case "$service" in
            postgres|postgresql)
                docker compose --env-file dify.env logs -f postgres
                ;;
            redis)
                docker compose --env-file dify.env logs -f redis
                ;;
            weaviate)
                docker compose --env-file dify.env logs -f weaviate
                ;;
            *)
                log_error "未知服务: $service"
                echo "可用服务: postgres, redis, weaviate"
                exit 1
                ;;
        esac
    fi
}

# 备份数据
backup_data() {
    log_info "执行数据备份..."
    
    local backup_date=$(date +%Y%m%d_%H%M%S)
    local backup_dir="backups/${backup_date}"
    
    mkdir -p "$backup_dir"
    
    # 备份PostgreSQL
    log_info "备份 PostgreSQL 数据库..."
    docker compose --env-file dify.env exec -T postgres pg_dump -U dify dify > "${backup_dir}/postgres_backup.sql"
    
    # 备份Redis
    log_info "备份 Redis 数据..."
    docker compose --env-file dify.env exec -T redis redis-cli --rdb /tmp/dump.rdb >/dev/null 2>&1 || true
    docker cp dify-redis:/data/dump.rdb "${backup_dir}/redis_backup.rdb" 2>/dev/null || true
    
    # 备份Weaviate (导出数据卷)
    log_info "备份 Weaviate 数据..."
    docker run --rm -v docker_db_weaviate_data:/data -v "$(pwd)/${backup_dir}:/backup" alpine tar czf /backup/weaviate_backup.tar.gz -C /data . 2>/dev/null || true
    
    # 备份配置文件
    log_info "备份配置文件..."
    tar czf "${backup_dir}/config_backup.tar.gz" dify.env docker-compose.yml init-scripts/ 2>/dev/null || true
    
    # 创建备份报告
    cat > "${backup_dir}/backup_info.txt" << EOF
Dify 服务器备份信息
备份时间: $(date)
备份目录: ${backup_dir}

备份内容:
- PostgreSQL: postgres_backup.sql
- Redis: redis_backup.rdb
- Weaviate: weaviate_backup.tar.gz
- 配置文件: config_backup.tar.gz

备份大小: $(du -sh "${backup_dir}" | cut -f1)
EOF
    
    log_success "备份完成: ${backup_dir}"
    
    # 清理旧备份 (保留最近7天)
    find backups/ -type d -name "20*" -mtime +7 -exec rm -rf {} \; 2>/dev/null || true
}

# 清理数据 (危险操作)
clean_data() {
    log_warning "这将删除所有数据，包括数据库内容！"
    read -p "确认要清理所有数据吗？输入 'YES' 确认: " confirm
    
    if [ "$confirm" = "YES" ]; then
        log_info "停止服务..."
        docker compose --env-file dify.env down
        
        log_info "删除数据卷..."
        docker volume rm docker_db_postgres_data docker_db_redis_data docker_db_weaviate_data 2>/dev/null || true
        
        log_success "数据清理完成"
    else
        log_info "操作已取消"
    fi
}

# 健康检查
health_check() {
    log_info "执行健康检查..."
    
    local all_healthy=true
    
    # 检查配置文件
    check_config_files
    
    # 检查容器状态
    log_info "检查容器运行状态..."
    local container_status=$(docker compose --env-file dify.env ps --format "table {{.Name}}\t{{.Status}}")
    echo "$container_status"
    
    if ! docker compose --env-file dify.env ps | grep -q "Up"; then
        log_error "部分或全部容器未运行"
        all_healthy=false
    fi
    
    # 检查PostgreSQL
    log_info "检查PostgreSQL连接..."
    local postgres_cmd="docker compose --env-file dify.env exec -T postgres pg_isready -U dify -d dify"
    echo "执行命令: $postgres_cmd"
    local postgres_result=$($postgres_cmd 2>&1)
    local postgres_exit_code=$?
    if [ $postgres_exit_code -eq 0 ]; then
        log_success "PostgreSQL: 健康"
        echo "输出: $postgres_result"
    else
        log_error "PostgreSQL: 异常"
        echo "退出码: $postgres_exit_code"
        echo "错误输出: $postgres_result"
        all_healthy=false
    fi
    
    # 检查Redis
    log_info "检查Redis连接..."
    local redis_password=$(grep "REDIS_PASSWORD=" dify.env | cut -d'=' -f2 | tr -d '\r\n\t ' | tr -d "'\"")
    echo "执行命令: docker exec dify-redis redis-cli -a [密码已隐藏] ping"
    echo "从配置文件读取的密码: '$redis_password'"
    echo "密码长度: ${#redis_password} 字符"
    local redis_result=$(docker exec dify-redis redis-cli -a "$redis_password" ping 2>&1)
    local redis_exit_code=$?
    if echo "$redis_result" | grep -q "PONG"; then
        log_success "Redis: 健康"
        echo "返回结果: PONG"
    else
        log_error "Redis: 异常"
        echo "退出码: $redis_exit_code"
        echo "实际返回: $redis_result"
        echo "调试: 原始grep结果: '$(grep "REDIS_PASSWORD=" dify.env)'"
        all_healthy=false
    fi
    
    # 检查Weaviate
    log_info "检查Weaviate连接..."
    local weaviate_port=$(grep "WEAVIATE_PORT=" dify.env | cut -d'=' -f2)
    local weaviate_url="http://127.0.0.1:${weaviate_port}/v1/.well-known/ready"
    local weaviate_cmd="curl -s -f $weaviate_url"
    echo "执行命令: $weaviate_cmd"
    local weaviate_result=$($weaviate_cmd 2>&1)
    local weaviate_exit_code=$?
    if [ $weaviate_exit_code -eq 0 ]; then
        log_success "Weaviate: 健康"
        echo "HTTP响应: 200 OK"
    else
        log_error "Weaviate: 异常"
        echo "退出码: $weaviate_exit_code"
        echo "错误输出: $weaviate_result"
        
        # 获取更详细的状态信息
        local weaviate_status=$(curl -s -w "%{http_code}" -o /dev/null $weaviate_url 2>/dev/null || echo "连接失败")
        echo "HTTP状态码: $weaviate_status"
        
        # 检查端口是否监听
        if command -v netstat &> /dev/null; then
            local port_status=$(netstat -tlnp | grep ":${weaviate_port}" || echo "端口未监听")
            echo "端口状态: $port_status"
        fi
        
        all_healthy=false
    fi
    
    echo ""
    if [ "$all_healthy" = true ]; then
        log_success "所有服务运行正常"
        return 0
    else
        log_error "部分服务异常"
        echo ""
        echo "=== 故障排除建议 ==="
        echo "1. 查看具体服务日志: ./docker-setup-updated.sh logs [postgres|redis|weaviate]"
        echo "2. 检查容器状态: docker ps -a"
        echo "3. 重启异常服务: docker restart [容器名]"
        echo "4. 完全重启: ./docker-setup-updated.sh restart"
        return 1
    fi
}

# 详细检测命令
detailed_check() {
    log_info "执行详细系统检测..."
    
    echo ""
    echo "=== 系统信息 ==="
    echo "操作系统: $(uname -a)"
    echo "Docker版本: $(docker --version)"
    echo "Docker Compose版本: $(docker compose version)"
    echo "当前用户: $(whoami)"
    echo "当前目录: $(pwd)"
    
    echo ""
    echo "=== 配置文件检查 ==="
    echo "dify.env 存在: $([ -f dify.env ] && echo '✅' || echo '❌')"
    echo "docker-compose.yml 存在: $([ -f docker-compose.yml ] && echo '✅' || echo '❌')"
    
    if [ -f dify.env ]; then
        echo "配置内容:"
        cat dify.env | grep -E "(POSTGRES_|REDIS_|WEAVIATE_|SERVER_)" | sed 's/^/  /'
    fi
    
    echo ""
    echo "=== 网络检查 ==="
    local weaviate_port=$(grep "WEAVIATE_PORT=" dify.env | cut -d'=' -f2)
    echo "端口监听状态:"
    netstat -tlnp | grep -E ":(5432|6379|${weaviate_port})" | sed 's/^/  /' || echo "  无相关端口监听"
    
    echo ""
    echo "=== 容器详细状态 ==="
    docker compose --env-file dify.env ps --format "table {{.Name}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
    
    echo ""
    echo "=== 数据卷信息 ==="
    docker volume ls | grep docker_db | sed 's/^/  /'
    
    echo ""
    echo "=== 资源使用情况 ==="
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"
    
    echo ""
    log_info "详细检测完成"
}

# 显示连接信息
show_connection_info() {
    if [ ! -f "dify.env" ]; then
        log_error "环境配置文件不存在"
        exit 1
    fi
    
    local server_ip=$(grep "SERVER_IP=" dify.env | cut -d'=' -f2)
    local postgres_port=$(grep "POSTGRES_PORT=" dify.env | cut -d'=' -f2)
    local redis_port=$(grep "REDIS_PORT=" dify.env | cut -d'=' -f2)
    local weaviate_port=$(grep "WEAVIATE_PORT=" dify.env | cut -d'=' -f2)
    local postgres_password=$(grep "POSTGRES_PASSWORD=" dify.env | cut -d'=' -f2)
    local redis_password=$(grep "REDIS_PASSWORD=" dify.env | cut -d'=' -f2)
    local weaviate_api_key=$(grep "WEAVIATE_API_KEY=" dify.env | cut -d'=' -f2)
    
    echo ""
    echo "=== Dify 家庭服务器连接信息 ==="
    echo ""
    echo "服务器IP: ${server_ip}"
    echo ""
    echo "PostgreSQL:"
    echo "  地址: ${server_ip}:${postgres_port}"
    echo "  数据库: dify"
    echo "  用户名: dify"
    echo "  密码: ${postgres_password}"
    echo "  连接字符串: postgresql://dify:${postgres_password}@${server_ip}:${postgres_port}/dify"
    echo ""
    echo "Redis:"
    echo "  地址: ${server_ip}:${redis_port}"
    echo "  密码: ${redis_password}"
    echo "  内存限制: $(grep "REDIS_MAXMEMORY=" dify.env | cut -d'=' -f2)"
    echo "  连接字符串: redis://:${redis_password}@${server_ip}:${redis_port}"
    echo ""
    echo "Weaviate:"
    echo "  地址: http://${server_ip}:${weaviate_port}"
    echo "  API Key: ${weaviate_api_key}"
    echo ""
    echo "=== 防火墙端口配置 ==="
    echo "sudo ufw allow 22/tcp      # SSH"
    echo "sudo ufw allow ${postgres_port}/tcp    # PostgreSQL"
    echo "sudo ufw allow ${redis_port}/tcp       # Redis"
    echo "sudo ufw allow ${weaviate_port}/tcp    # Weaviate"
    echo "sudo ufw enable"
    echo ""
    
    # 显示Redis配置状态
    echo "=== Redis 配置状态 ==="
    echo "✅ 所有Redis配置都通过环境变量管理"
    echo "✅ 无需手动同步配置文件"
    echo "✅ 配置统一在 dify.env 中"
    echo ""
}

# 主函数
main() {
    case "${1:-help}" in
        setup)
            setup_deployment
            ;;
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
            show_logs "$2"
            ;;
        backup)
            backup_data
            ;;
        clean)
            clean_data
            ;;
        health)
            health_check
            ;;
        detailed)
            detailed_check
            ;;
        info)
            show_connection_info
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "未知命令: $1"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@" 