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

**测试环境配置（推荐用于开发/测试）：**

```bash
# 在 .env 中配置 Stripe 测试模式
BILLING_ENABLED=true
STRIPE_LIVE_MODE=false

# 测试模式密钥（从 Stripe Dashboard 的 Test mode 获取）
STRIPE_TEST_SECRET_KEY=sk_test_your_key_here
STRIPE_LIVE_SECRET_KEY=sk_live_your_key_here  # 可以留空，生产环境再配置

# Publishable Key（测试模式使用 pk_test_ 开头的值）
STRIPE_PUBLISHABLE_KEY=pk_test_your_key_here

# Webhook Secret（测试环境的 webhook endpoint 的签名密钥）
STRIPE_WEBHOOK_SECRET=whsec_your_test_secret_here
```

**生产环境配置：**

```bash
# 在 .env 中配置 Stripe 生产模式
BILLING_ENABLED=true
STRIPE_LIVE_MODE=true  # ⚠️ 重要：切换到生产模式

# 生产模式密钥（从 Stripe Dashboard 的 Live mode 获取）
STRIPE_LIVE_SECRET_KEY=sk_live_your_key_here
STRIPE_TEST_SECRET_KEY=sk_test_your_key_here  # 可以保留用于回退

# Publishable Key（生产模式使用 pk_live_ 开头的值）
STRIPE_PUBLISHABLE_KEY=pk_live_your_key_here

# Webhook Secret（生产环境的 webhook endpoint 的签名密钥）
STRIPE_WEBHOOK_SECRET=whsec_your_live_secret_here
```

**重要说明：**

1. **变量命名逻辑**：
   - `STRIPE_TEST_SECRET_KEY` 和 `STRIPE_LIVE_SECRET_KEY` 是**两套不同的密钥**
   - 通过 `STRIPE_LIVE_MODE` 开关自动选择使用哪一套
   - `STRIPE_PUBLISHABLE_KEY` 和 `STRIPE_WEBHOOK_SECRET` 只有一个变量名，但需要根据环境填写对应的值

2. **测试 vs 生产模式**：
   - 测试模式（`STRIPE_LIVE_MODE=false`）：使用 `sk_test_` 和 `pk_test_` 开头的密钥，不会产生真实扣款
   - 生产模式（`STRIPE_LIVE_MODE=true`）：使用 `sk_live_` 和 `pk_live_` 开头的密钥，会产生真实扣款

3. **Webhook 配置**：
   - 测试和生产环境需要分别创建不同的 Webhook Endpoint
   - 每个 Endpoint 都有独立的 `STRIPE_WEBHOOK_SECRET`
   - Webhook URL: `https://你的域名/api/billing/webhooks/stripe/`

**获取 STRIPE_WEBHOOK_SECRET：**

使用 curl 直接调用 Stripe API 创建 Webhook：

```bash
# 加载 .env 文件中的环境变量
source .env

# 测试模式
curl -X POST https://api.stripe.com/v1/webhook_endpoints \
  -u "${STRIPE_TEST_SECRET_KEY}:" \
  -d "url=https://${SITE_DOMAIN}/api/billing/webhooks/stripe/" \
  -d "enabled_events[]=customer.subscription.created" \
  -d "enabled_events[]=customer.subscription.updated" \
  -d "enabled_events[]=customer.subscription.deleted" \
  -d "enabled_events[]=invoice.payment_succeeded" \
  -d "enabled_events[]=invoice.payment_failed"

# 生产模式（切换到 Live mode 后）
curl -X POST https://api.stripe.com/v1/webhook_endpoints \
  -u "${STRIPE_LIVE_SECRET_KEY}:" \
  -d "url=https://${SITE_DOMAIN}/api/billing/webhooks/stripe/" \
  -d "enabled_events[]=customer.subscription.created" \
  -d "enabled_events[]=customer.subscription.updated" \
  -d "enabled_events[]=customer.subscription.deleted" \
  -d "enabled_events[]=invoice.payment_succeeded" \
  -d "enabled_events[]=invoice.payment_failed"
```

**从响应中获取 Secret：**

命令执行后会返回 JSON 响应，格式如下：

```json
{
  "id": "we_xxx",
  "secret": "whsec_Sl8EWUNzVmScuB1907f1lezuy95kc13I",
  "url": "https://app.aimychats.com/api/billing/webhooks/stripe/",
  ...
}
```

**使用 `secret` 字段的值**（格式：`whsec_xxx`），添加到 `.env` 文件：

```bash
STRIPE_WEBHOOK_SECRET=whsec_Sl8EWUNzVmScuB1907f1lezuy95kc13I
```

**提示：** 如果安装了 `jq`，可以使用以下命令直接提取 secret：

```bash
curl ... | jq -r '.secret'
```

**重要提示：**
- ⚠️ **测试和生产环境需要分别创建**：在 Test mode 和 Live mode 下各创建一个 Webhook
- ⚠️ **Webhook URL 必须是 HTTPS**：确保你的域名已配置 SSL 证书
- ⚠️ **Secret 格式**：所有 Webhook Secret 都以 `whsec_` 开头
- ⚠️ **安全**：Webhook Secret 用于验证请求来自 Stripe，不要泄露

**配置计费方案：**

编辑 `../devify/devify/conf/billing/plans.yaml` 定义订阅方案和价格。

**自动初始化：**

容器启动时会自动：
- 创建本地 Plan 数据
- 在 Stripe 创建对应的 Products 和 Prices

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

## 参考文档

### 手动创建 Stripe Webhook（备选方案）

如果自动化创建失败，可以在 Stripe Dashboard 中手动创建 Webhook：

1. **登录 Stripe Dashboard**
   - 访问：https://dashboard.stripe.com
   - 确保切换到正确的模式（Test mode 或 Live mode）

2. **创建 Webhook Endpoint**
   - 左侧菜单 → **Developers** → **Webhooks**
   - 点击 **"Add endpoint"** 按钮

3. **配置 Webhook**
   - **Endpoint URL**：`https://你的域名/api/billing/webhooks/stripe/`
     - 例如：`https://app.aimychats.com/api/billing/webhooks/stripe/`
   - **Description**：`Devify Production Webhook`（可选）
   - **Events to send**：选择以下事件（至少需要这些）：
     - ✅ `customer.subscription.created`
     - ✅ `customer.subscription.updated`
     - ✅ `customer.subscription.deleted`
     - ✅ `invoice.payment_succeeded`
     - ✅ `invoice.payment_failed`

4. **获取 Webhook Secret**
   - 点击 **"Add endpoint"** 创建后
   - 在 Webhook 详情页面，找到 **"Signing secret"** 部分
   - 点击 **"Reveal"** 或 **"Click to reveal"** 按钮
   - 复制以 `whsec_` 开头的值
   - 这就是你的 `STRIPE_WEBHOOK_SECRET`

5. **添加到 .env 文件**
   ```bash
   STRIPE_WEBHOOK_SECRET=whsec_你复制的密钥
   ```

## 相关文档

- **脚本使用说明：** `scripts/README.md`
- **Nginx 配置说明：** 查看 `nginx/` 目录中的配置文件注释
- **环境变量说明：** 参考 `env.sample`
- **核心代码：** `../devify/` 目录
- **计费系统详细说明：** `docs/BILLING_SYSTEM.md`

## 技术支持

如有问题请提交 Issue 或联系项目维护者。
