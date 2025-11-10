# Devify Deploy - Commercial Deployment Configuration

This repository contains the deployment configuration for the commercial version of Devify (AImyChats).

## Project Structure

```
devify-deploy/
├── docker-compose.dev.yml      # Development environment configuration
├── docker-compose.yml          # Production environment configuration
├── docker/                     # Docker configuration files
│   ├── entrypoint.sh          # Container entrypoint script
│   ├── nginx/                 # Nginx configuration
│   ├── haraka/                # Haraka mail server configuration
│   ├── mysql/                 # MySQL initialization scripts
│   └── logrotate.conf         # Log rotation configuration
├── data/                       # Runtime data (NOT in git)
│   ├── django/staticfiles/
│   ├── email_attachments/
│   ├── haraka/emails/
│   ├── logs/
│   ├── mysql/data/
│   ├── redis/
│   └── certs/
├── cache/                      # Cache directory (NOT in git)
├── scripts/                    # Deployment scripts
│   └── manage-haraka-certs.sh
├── .env.sample                 # Environment variables template
├── .gitignore                  # Git ignore rules
└── README.md                   # This file
```

## Architecture

This deployment project references the following code repositories:

- `../devify/` - Backend API code (Django/Python)
- `../devify-ui/` - Frontend UI code (Vue.js)

The code is not duplicated here; Docker Compose references these directories via relative paths.

## Prerequisites

- Docker and Docker Compose
- Sufficient disk space for database and email storage
- Ports: 8000 (HTTP), 25 (SMTP), 5555 (Flower - optional)

## Quick Start

### Development Environment

1. **Copy environment configuration:**
   ```bash
   cp .env.sample .env
   vim .env  # Edit configuration as needed
   ```

2. **Start services:**
   ```bash
   docker-compose -f docker-compose.dev.yml up -d
   ```

3. **Check logs:**
   ```bash
   docker-compose -f docker-compose.dev.yml logs -f
   ```

4. **Access services:**
   - Frontend: http://localhost:8000
   - API: http://localhost:8000/api
   - Flower (Celery monitoring): http://localhost:5555

### Production Environment

1. **Configure environment:**
   ```bash
   cp .env.sample .env
   # Edit .env with production settings:
   # - Set DJANGO_DEBUG=False
   # - Configure production database
   # - Set strong SECRET_KEY
   # - Configure Stripe keys
   # - Configure Haraka/SMTP
   # - Configure SSL certificates
   ```

2. **Build and start services:**
   ```bash
   docker-compose up -d --build
   ```

3. **Initialize database (first time only):**
   ```bash
   docker-compose exec devify-api python manage.py migrate
   docker-compose exec devify-api python manage.py createsuperuser
   ```

## Services

| Service | Description | Port |
|---------|-------------|------|
| devify-api | Django API server | 8000 (internal) |
| devify-worker | Celery worker | N/A |
| devify-scheduler | Celery beat scheduler | N/A |
| devify-ui | Vue.js frontend | 80 (internal) |
| nginx | Reverse proxy | 8000/10080 (HTTP), 10443 (HTTPS) |
| mysql | MariaDB database | 3306 (internal) |
| redis | Redis cache/broker | 6379 (internal) |
| haraka | Mail server (SMTP) | 25 |
| flower | Celery monitoring (dev only) | 5555 |

## Configuration

### Key Environment Variables

**Database:**
- `DB_ENGINE` - Database engine (sqlite/mysql/postgresql)
- `MYSQL_*` - MySQL configuration

**Django:**
- `SECRET_KEY` - Django secret key (REQUIRED in production)
- `DJANGO_DEBUG` - Debug mode (False in production)
- `ALLOWED_HOSTS` - Allowed hostnames
- `FRONTEND_URL` - Frontend URL for OAuth redirects

**Commercial Features:**
- `BILLING_ENABLED=true` - Enable billing system
- `PAYMENT_PROVIDERS_ENABLED=true` - Enable payment providers
- `STRIPE_*` - Stripe API keys (commercial only)

**Haraka (Commercial):**
- `HARAKA_SMTP_PORT` - SMTP port (default: 25)
- `AUTO_ASSIGN_EMAIL_DOMAIN` - Email domain for virtual mailboxes

**AI Services:**
- `AZURE_OPENAI_*` - Azure OpenAI configuration
- `AZURE_DOCUMENT_INTELLIGENCE_*` - OCR configuration

See `.env.sample` for complete list of configuration options.

## Data Directory

**IMPORTANT:** The `data/` directory contains all runtime data and is **NOT** included in version control:

```
data/
├── django/staticfiles/    # Django static files
├── email_attachments/     # Email attachments
├── haraka/
│   ├── emails/            # Haraka mail storage
│   │   ├── inbox/         # Incoming emails
│   │   ├── processed/     # Processed emails
│   │   └── failed/        # Failed emails
│   └── logs/              # Haraka logs
├── logs/                  # Application logs
│   ├── api/               # API logs
│   ├── worker/            # Worker logs
│   ├── scheduler/         # Scheduler logs
│   ├── nginx/             # Nginx logs
│   └── mysql/             # Database logs
├── mysql/data/            # Database files
├── redis/                 # Redis persistence
└── certs/                 # SSL certificates
    └── haraka/            # Haraka SSL certs
```

### First Deployment

On first deployment, the `data/` directory will be created automatically by Docker volumes. Ensure proper permissions:

```bash
# If needed, fix permissions
sudo chown -R $USER:$USER data/
```

### Backup Strategy

Regular backups should include:

1. **Database:**
   ```bash
   docker-compose exec mysql mysqldump -u root -p devify > backup.sql
   ```

2. **Email attachments:**
   ```bash
   tar -czf email_attachments_backup.tar.gz data/email_attachments/
   ```

3. **Haraka emails:**
   ```bash
   tar -czf haraka_emails_backup.tar.gz data/haraka/emails/
   ```

## Maintenance

### View Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f devify-api
docker-compose logs -f devify-worker
```

### Restart Services

```bash
# Restart all
docker-compose restart

# Restart specific service
docker-compose restart devify-api
docker-compose restart devify-worker
```

### Update Code

```bash
# Pull latest code
cd ../devify && git pull
cd ../devify-ui && git pull

# Rebuild and restart
cd ../devify-deploy
docker-compose down
docker-compose up -d --build
```

### Database Migration

```bash
docker-compose exec devify-api python manage.py migrate
```

### Haraka Certificate Management

```bash
# Generate or renew Haraka SSL certificates
./scripts/manage-haraka-certs.sh
```

## Troubleshooting

### Service won't start

```bash
# Check logs
docker-compose logs [service-name]

# Check if port is already in use
netstat -tulpn | grep [port]
```

### Database connection issues

```bash
# Check MySQL is running
docker-compose ps mysql

# Connect to MySQL
docker-compose exec mysql mysql -u root -p
```

### Email not receiving

```bash
# Check Haraka logs
docker-compose logs haraka

# Test SMTP connection
telnet localhost 25
```

### Worker not processing tasks

```bash
# Check worker logs
docker-compose logs devify-worker

# Check Redis connection
docker-compose exec redis redis-cli ping

# Monitor tasks in Flower (dev)
# Visit http://localhost:5555
```

## Development vs Production

### Development Mode

- Hot reload enabled for frontend
- Code mounted as volumes (changes reflect immediately)
- Debug mode enabled
- Flower monitoring available
- Console email backend

### Production Mode

- Pre-built images
- Debug mode disabled
- Production WSGI server (Gunicorn)
- No code volumes (uses container code)
- SMTP email backend
- SSL/HTTPS configured

## Security Notes

**Never commit to git:**
- `.env` file (contains secrets)
- `data/` directory (contains user data)
- SSL certificates
- API keys

**Production checklist:**
- [ ] Change SECRET_KEY
- [ ] Set DJANGO_DEBUG=False
- [ ] Configure ALLOWED_HOSTS
- [ ] Use strong database passwords
- [ ] Configure Stripe webhook secrets
- [ ] Set up SSL certificates
- [ ] Configure firewall rules
- [ ] Enable log rotation
- [ ] Set up regular backups

## License

Commercial license. See LICENSE file for details.

## Support

For deployment support, contact: support@aimychats.com
