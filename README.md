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
cp .env.example .env
vim .env  # 根据实际情况修改配置
```

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

### 3. 启动服务

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

## 相关文档

- **脚本使用说明：** `scripts/README.md`
- **Nginx 配置说明：** 查看 `nginx/` 目录中的配置文件注释
- **环境变量说明：** 参考 `.env.example`

## 技术支持

如有问题请提交 Issue 或联系项目维护者。
