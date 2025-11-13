# Devify Deployment

生产环境部署配置和脚本。

## 目录结构

```
devify-deploy/
├── docker-compose.yml          # Docker Compose 配置
├── .env                        # 环境变量（需创建）
├── nginx/                      # Nginx 配置文件
│   ├── default-http.conf       # 默认 HTTP server
│   ├── default-https.conf      # 默认 HTTPS server
│   ├── aimychats.com.conf      # 官网配置
│   └── app.aimychats.com.conf  # 应用配置
├── scripts/                    # 维护和管理脚本
│   ├── README.md               # 脚本使用说明
│   ├── generate-self-signed-certs.sh
│   ├── generate-letsencrypt-certs.sh
│   ├── generate-certs-docker.sh
│   └── manage-haraka-certs.sh
├── data/                       # 运行时数据（不纳入版控）
│   ├── certs/                  # SSL 证书
│   ├── django/                 # Django 静态文件
│   ├── logs/                   # 日志文件
│   └── mysql/                  # 数据库文件
└── docker/                     # Docker 相关配置
    ├── mysql/                  # MySQL 配置
    └── haraka/                 # Haraka 邮件服务器配置
```

## 快速开始

### 1. 准备环境变量

```bash
cp env.sample .env
vim .env  # 根据实际情况修改配置
```

**关键配置项（OAuth 相关）：**

```bash
# Django Site 配置（必需，用于 OAuth 回调）
SITE_DOMAIN=192.168.8.182:10443  # 或使用域名如 app.aimychats.com
SITE_NAME=Devify Production

# Google OAuth 配置
GOOGLE_OAUTH_CLIENT_ID=your_google_client_id
GOOGLE_OAUTH_CLIENT_SECRET=your_google_client_secret

# 前端配置
FRONTEND_URL=https://192.168.8.182:10443
VITE_API_BASE_URL=https://192.168.8.182:10443

# CSRF 信任来源
CSRF_TRUSTED_ORIGINS='https://192.168.8.182:10443'
```

> **注意：**
> - `SITE_DOMAIN` 会在容器启动时自动配置到 Django Site 中
> - Google OAuth 配置会自动初始化到数据库
> - 确保在 Google Cloud Console 中添加对应的回调 URL：`https://your-domain/accounts/google/login/callback/`

### 2. 生成 SSL 证书

**开发/测试环境：**
```bash
./scripts/generate-self-signed-certs.sh
```

**生产环境：**
```bash
# 修改脚本中的邮箱地址
vim scripts/generate-certs-docker.sh

# 停止 nginx 并生成证书
docker-compose stop nginx
./scripts/generate-certs-docker.sh

# 启动服务
docker-compose up -d
```

### 3. 配置 Stripe 计费系统（可选）

如果启用了付费订阅功能（`BILLING_ENABLED=true`），需要配置 Stripe：

```bash
# 在 .env 中配置 Stripe
BILLING_ENABLED=true
STRIPE_TEST_SECRET_KEY=sk_test_your_key_here
STRIPE_PUBLISHABLE_KEY=pk_test_your_key_here
STRIPE_WEBHOOK_SECRET=whsec_your_secret_here  # 初始化后会生成
```

**配置计费方案：**

编辑 `../devify/devify/conf/billing/plans.yaml` 定义订阅方案和价格。

**自动初始化：**

容器启动时会自动：
- 创建本地 Plan 数据
- 在 Stripe 创建对应的 Products 和 Prices
- 配置 Webhook 端点

**手动初始化（可选）：**

```bash
# 进入容器手动初始化
docker exec devify-api python manage.py init_billing_stripe

# 查看当前配置
docker exec devify-api python manage.py init_billing_stripe --skip-products --skip-webhook
```

> **注意：**
> - 首次初始化后会输出 `STRIPE_WEBHOOK_SECRET`，需要添加到 `.env` 文件
> - 修改价格后重新运行命令会自动更新（保持幂等性）
> - 详细配置说明请查看 `../devify/devify/conf/billing/README.md`

### 4. 启动服务

```bash
# 启动所有服务
docker-compose up -d

# 查看服务状态
docker-compose ps

# 查看日志
docker-compose logs -f
```

## 服务端口

| 服务 | HTTP 端口 | HTTPS 端口 |
|------|----------|-----------|
| Nginx | 10080 | 10443 |
| Haraka SMTP | 25 | - |

## 访问方式

- **官网（devify-home）：**
  - HTTP: `http://your-ip:10080`
  - HTTPS: `https://your-ip:10443`
  - 域名: `http(s)://aimychats.com`

- **应用（devify-ui）：**
  - 域名: `http(s)://app.aimychats.com`
  - API: `http(s)://your-ip:10080/api/`

## 维护脚本

所有维护脚本位于 `scripts/` 目录，详细说明请查看：

```bash
cat scripts/README.md
```

## 常用命令

```bash
# 查看服务状态
docker-compose ps

# 重启服务
docker-compose restart [service_name]

# 查看日志
docker-compose logs -f [service_name]

# 停止所有服务
docker-compose down

# 更新镜像
docker-compose pull
docker-compose up -d

# 验证 nginx 配置
docker exec devify-nginx nginx -t

# 重新加载 nginx
docker exec devify-nginx nginx -s reload
```

## 故障排查

### 健康检查失败

```bash
# 检查容器状态
docker-compose ps

# 查看容器日志
docker-compose logs devify-ui
docker-compose logs devify-home

# 手动测试健康检查
docker exec devify-ui wget -Y off --quiet --tries=1 --spider http://127.0.0.1
```

### SSL 证书问题

```bash
# 检查证书文件
ls -lh data/certs/nginx/

# 验证证书
openssl x509 -in data/certs/nginx/aimychats.com.crt -noout -dates

# 重新生成证书
./scripts/generate-self-signed-certs.sh
docker-compose restart nginx
```

### 端口占用

```bash
# 检查端口占用
netstat -tlnp | grep -E ":(10080|10443|25)"

# 修改端口（在 .env 文件中）
NGINX_HTTP_PORT=8080
NGINX_HTTPS_PORT=8443
```

## 开发和维护说明

### 代码维护位置

**重要提示**：本目录下只包含生产环境的**配置文件**，核心代码和脚本在 `devify/` 目录中维护：

- **entrypoint.sh**：在 `devify/docker/entrypoint.sh` 中维护
  - 镜像构建时会被复制到镜像中
  - 本目录不再保留副本，避免重复维护

- **应用代码**：在 `devify/devify/` 中维护
- **Dockerfile**：在 `devify/Dockerfile` 中维护

本目录主要包含：
- ✅ 生产环境配置（nginx、mysql、haraka 等）
- ✅ 部署脚本（SSL 证书生成、数据库迁移等）
- ✅ 环境变量配置（.env）
- ✅ Docker Compose 编排配置

## 相关文档

- **脚本使用说明：** `scripts/README.md`
- **Nginx 配置说明：** 查看 `nginx/` 目录中的配置文件注释
- **环境变量说明：** 参考 `env.sample`
- **核心代码：** `../devify/` 目录

## 技术支持

如有问题请提交 Issue 或联系项目维护者。
