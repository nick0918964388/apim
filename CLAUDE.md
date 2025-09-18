# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kong APIM Platform - A high-availability API gateway management platform with PostgreSQL master-slave replication, ELK stack monitoring, and automated backup system. The platform is containerized using Docker Compose.

## Key Architecture Components

### Service Architecture
- **Kong Gateway 3.8**: API gateway exposed on ports 8000 (proxy) and 8001 (admin)
- **PostgreSQL 13 HA Cluster**: Master (port 5432) for read/write, Slave (port 5433) for read-only with streaming replication
- **ELK Stack 8.11**: Elasticsearch (9200), Logstash (8080), Kibana (5601) for centralized logging and monitoring
- **Automated Backup Service**: Cron-based full and incremental backups with retention policies

### Data Flow
1. Kong Gateway logs API traffic to Logstash via HTTP
2. Logstash processes and indexes logs to Elasticsearch
3. PostgreSQL master replicates data to slave using streaming replication
4. Backup service performs scheduled backups of master database

## Development Commands

### Start Services
```bash
cd deployments/docker
docker compose --env-file ../../config/env/.env.dev up -d
```

### Stop Services
```bash
cd deployments/docker
docker compose --env-file ../../config/env/.env.dev down
```

### View Logs
```bash
cd deployments/docker
docker compose --env-file ../../config/env/.env.dev logs -f [service-name]
# Example: docker compose --env-file ../../config/env/.env.dev logs -f kong
```

### Validate Deployment
```bash
./scripts/validate-deployment.sh
```

### Database Migrations
```bash
cd deployments/docker
docker compose --env-file ../../config/env/.env.dev run --rm kong-migration kong migrations bootstrap
```

### Manual Backup Operations
```bash
# Full backup
./scripts/backup/full_backup.sh

# Incremental backup
./scripts/backup/incremental_backup.sh

# Verify backup
./scripts/backup/verify_backup.sh
```

### Check Service Health
```bash
# PostgreSQL Master
docker exec kong-database-master pg_isready -U kong

# PostgreSQL Slave
docker exec kong-database-slave pg_isready -U kong

# Kong
curl http://localhost:8001/status

# Elasticsearch
curl http://localhost:9200/_cluster/health

# Kibana
curl http://localhost:5601/api/status
```

### Check Replication Status
```bash
# View replication status on master
docker exec kong-database-master psql -U kong -d kong -c "SELECT * FROM pg_stat_replication;"

# Check replication lag on slave
docker exec kong-database-slave psql -U kong -d kong -c "SELECT NOW() - pg_last_xact_replay_timestamp() AS replication_lag;"
```

## Configuration Structure

### Environment Configuration
- **Main config**: `config/env/.env.dev` - Contains all service credentials and settings
- **Production setup**: Copy `.env.dev` to `.env.local` and update all passwords

### Service Configurations
- **Kong**: `config/kong/kong.conf`
- **PostgreSQL Master**: `config/postgresql/master/{postgresql.conf,pg_hba.conf}`
- **PostgreSQL Slave**: `config/postgresql/slave/{postgresql.conf,pg_hba.conf}`
- **Elasticsearch**: `deployments/monitoring/elasticsearch/elasticsearch.yml`
- **Logstash**: `deployments/monitoring/logstash/kong-logs.conf`
- **Kibana**: `deployments/monitoring/kibana/kibana.yml`

### Docker Compose
- **Main file**: `deployments/docker/docker-compose.yml`
- **Network**: Uses custom bridge network `kong-net` with subnet 172.20.0.0/16
- **Volumes**: Persistent data stored in Docker volumes and host paths under `/srv/apim/`

## Service Dependencies

The services must start in this order:
1. `kong-database-master` (PostgreSQL master)
2. `kong-database-slave` (depends on master being healthy)
3. `elasticsearch`
4. `logstash` (depends on Elasticsearch)
5. `kibana` (depends on Elasticsearch)
6. `kong-migration` (runs once for database setup)
7. `kong` (depends on database and Logstash)
8. `kong-backup` (depends on master database)

## Monitoring and Observability

### Access Points
- Kong Proxy API: http://localhost:8000
- Kong Admin API: http://localhost:8001
- Kibana Dashboard: http://localhost:5601
- Elasticsearch: http://localhost:9200

### Key Metrics to Monitor
- API response time (P50/P95/P99)
- Error rates
- PostgreSQL replication lag
- Backup success/failure
- Service health status

## Backup Strategy

### Automated Schedule
- Full backup: Daily at 02:00
- Incremental backup: Hourly
- WAL archiving: Continuous

### Retention Policies
- Full backups: 30 days
- Incremental backups: 7 days
- WAL archives: 14 days

### Backup Locations
- Daily backups: `/srv/apim/database/backups/daily/`
- Hourly backups: `/srv/apim/database/backups/hourly/`
- WAL archives: `/srv/apim/database/wal_archive/`

## Testing Approach

The project uses shell scripts for validation and testing:
- `scripts/validate-deployment.sh` - Comprehensive deployment validation
- `scripts/validate-config.sh` - Configuration syntax validation

No unit test framework is configured. Testing is done through deployment validation and health checks.

## Common Troubleshooting

### PostgreSQL Replication Issues
Check replication user permissions and network connectivity between master/slave containers.

### Kong Migration Failures
Ensure PostgreSQL master is healthy before running migrations. Check database connectivity and credentials.

### ELK Stack Memory Issues
Adjust `ES_JAVA_OPTS` in environment configuration if Elasticsearch runs out of memory.

### Backup Failures
Verify PostgreSQL credentials and ensure backup directories have proper permissions (999:999).