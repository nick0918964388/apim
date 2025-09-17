-- PostgreSQL 主從複製初始化腳本
-- Kong APIM Platform - Master-Slave Replication Setup

-- 創建複製使用者
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'replicator_password';

-- 創建 Kong 資料庫和使用者
CREATE DATABASE kong;
CREATE USER kong WITH PASSWORD 'kong';
GRANT ALL PRIVILEGES ON DATABASE kong TO kong;

-- 設定 Kong 使用者為資料庫擁有者
ALTER DATABASE kong OWNER TO kong;