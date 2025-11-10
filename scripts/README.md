# Scripts Directory

此目录包含 Devify 项目的维护和管理脚本。

**重要提示：** 所有脚本都支持从任意目录执行，会自动定位到项目根目录。

## SSL 证书管理脚本

### 1. generate-self-signed-certs.sh
生成自签名 SSL 证书（用于开发/测试环境）

**用途：** 快速生成本地测试证书  
**使用方法：**
```bash
# 可以从项目根目录执行
cd /path/to/devify-deploy
./scripts/generate-self-signed-certs.sh

# 也可以从任意目录执行
/path/to/devify-deploy/scripts/generate-self-signed-certs.sh
```

**输出位置：** `{PROJECT_ROOT}/data/certs/nginx/`

---

### 2. generate-letsencrypt-certs.sh
使用系统 certbot 生成 Let's Encrypt 证书（生产环境）

**前提条件：**
- 已安装 certbot
- 域名已解析到服务器
- 80 端口可公网访问

**使用方法：**
```bash
cd /path/to/devify-deploy

# 1. 修改邮箱地址
vim scripts/generate-letsencrypt-certs.sh
# 将 EMAIL="your-email@example.com" 改为你的邮箱

# 2. 停止 nginx（释放 80 端口）
docker-compose stop nginx

# 3. 运行脚本
./scripts/generate-letsencrypt-certs.sh

# 4. 启动 nginx
docker-compose up -d nginx
```

**输出位置：** `{PROJECT_ROOT}/data/certs/nginx/`

---

### 3. generate-certs-docker.sh （推荐）
使用 Docker certbot 生成 Let's Encrypt 证书

**前提条件：**
- 已安装 Docker
- 域名已解析到服务器
- 80 端口可公网访问

**使用方法：**
```bash
cd /path/to/devify-deploy

# 1. 修改邮箱地址
vim scripts/generate-certs-docker.sh
# 将 EMAIL="your-email@example.com" 改为你的邮箱

# 2. 停止 nginx（释放 80 端口）
docker-compose stop nginx

# 3. 运行脚本（会自动定位项目路径）
./scripts/generate-certs-docker.sh

# 4. 启动 nginx
docker-compose up -d nginx
```

**输出位置：** `{PROJECT_ROOT}/data/certs/nginx/`

---

### 4. manage-haraka-certs.sh
管理 Haraka 邮件服务器的 SSL 证书

**用途：** 生成或更新 Haraka 的 TLS 证书

**使用方法：**
```bash
./scripts/manage-haraka-certs.sh
```

**输出位置：** `{PROJECT_ROOT}/data/certs/haraka/`

---

## 脚本特性

### 自动路径识别

所有脚本都实现了自动路径识别：
- 获取脚本所在目录
- 自动计算项目根目录
- 无论从哪里执行都能正确工作

**示例：**
```bash
# 以下三种方式都能正确工作
cd /path/to/devify-deploy && ./scripts/generate-self-signed-certs.sh
cd /tmp && /path/to/devify-deploy/scripts/generate-self-signed-certs.sh
/path/to/devify-deploy/scripts/generate-self-signed-certs.sh
```

### 输出信息

每个脚本执行时会显示：
- 项目根目录路径
- 证书输出目录路径
- 执行进度和结果

---

## 证书续期

### Let's Encrypt 证书自动续期

Let's Encrypt 证书有效期为 90 天，需要定期续期。

**手动续期：**
```bash
cd /path/to/devify-deploy

# 使用 Docker certbot 续期
docker run -it --rm \
  -v "$(pwd)/data/certbot/conf:/etc/letsencrypt" \
  -v "$(pwd)/data/certbot/www:/var/www/certbot" \
  certbot/certbot renew

# 复制更新后的证书
./scripts/generate-certs-docker.sh
```

**设置自动续期（推荐）：**
```bash
sudo crontab -e

# 添加以下行（每天凌晨 2 点检查续期）
0 2 * * * cd /path/to/devify-deploy && docker run --rm \
  -v "$(pwd)/data/certbot/conf:/etc/letsencrypt" \
  -v "$(pwd)/data/certbot/www:/var/www/certbot" \
  certbot/certbot renew --quiet && \
  docker exec devify-nginx nginx -s reload
```

---

## 注意事项

1. **权限设置：** 所有脚本都应有执行权限（chmod +x）
2. **邮箱配置：** Let's Encrypt 脚本需要修改邮箱地址
3. **端口占用：** 生成 Let's Encrypt 证书时需要停止 nginx
4. **备份证书：** 更新证书前建议备份现有证书
5. **测试配置：** 更新证书后使用 `docker exec devify-nginx nginx -t` 验证配置

---

## 故障排查

**问题：脚本执行失败**
```bash
# 检查脚本权限
ls -l scripts/*.sh

# 添加执行权限
chmod +x scripts/*.sh
```

**问题：Let's Encrypt 生成失败**
```bash
# 检查域名解析
nslookup aimychats.com

# 检查 80 端口
netstat -tlnp | grep :80

# 查看详细错误
./scripts/generate-certs-docker.sh
```

**问题：证书过期**
```bash
# 检查证书有效期
openssl x509 -in data/certs/nginx/aimychats.com.crt -noout -dates

# 强制续期
docker run -it --rm \
  -v "$(pwd)/data/certbot/conf:/etc/letsencrypt" \
  certbot/certbot renew --force-renewal
```

**问题：路径不正确**
```bash
# 脚本会自动显示使用的路径
./scripts/generate-self-signed-certs.sh
# 输出会包含：
# Project root: /path/to/devify-deploy
# Certificate directory: /path/to/devify-deploy/data/certs/nginx
```

---

## 相关文档

详细的部署配置请参考项目根目录的 `README.md`。
