-- Dify 数据库初始化脚本
-- 创建必要的扩展和配置

-- 创建 UUID 扩展 (Dify 需要)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 创建向量扩展 (如果使用 pgvector)
-- CREATE EXTENSION IF NOT EXISTS vector;

-- 设置默认时区
SET timezone = 'Asia/Shanghai';

-- 创建示例表 (可选)
-- CREATE TABLE IF NOT EXISTS health_check (
--     id SERIAL PRIMARY KEY,
--     status VARCHAR(50) DEFAULT 'healthy',
--     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
-- );

-- 插入健康检查数据
-- INSERT INTO health_check (status) VALUES ('initialized');

-- 输出初始化完成信息
DO $$
BEGIN
    RAISE NOTICE 'Dify database initialized successfully!';
END $$; 