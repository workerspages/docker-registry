

# 如何构建一个支持动态生成密码、适配 PaaS 平台（防止无限循环）、并支持云端存储的 Docker 私有仓库。


# PaaS-Ready Private Docker Registry

这是一个专为 PaaS 平台（如 Zeabur, Railway, Render, Heroku 等）定制的 Docker 私有仓库方案。

它解决了官方 `registry` 镜像在 PaaS 上部署时的两个核心痛点：
1.  **认证问题**：通过环境变量动态生成 `htpasswd` 密码文件（无需挂载本地文件）。
2.  **启动逻辑**：通过自定义启动脚本，避免覆盖官方 `entrypoint` 导致的死循环问题。
3.  **持久化存储**：支持通过环境变量配置 S3/OSS 对象存储，防止 PaaS 重启导致镜像丢失。

## 📂 项目结构

```text
.
├── Dockerfile      # 构建逻辑
└── start.sh        # 自定义启动脚本（生成密码并启动服务）
```

## 🛠️ 构建步骤

### 1. 编写启动脚本 (`start.sh`)

此脚本在容器启动时运行，用于读取环境变量并生成认证文件，最后调用官方原始入口。

> **⚠️ 注意**：文件名为 `start.sh`，**不要** 命名为 `entrypoint.sh`，否则会覆盖官方文件导致无限循环。

```bash
#!/bin/sh
set -e

# 检查是否设置了用户名和密码
if [ -n "$AUTH_USER" ] && [ -n "$AUTH_PASS" ]; then
    echo "🔐 Configuring authentication for user: $AUTH_USER"
    mkdir -p /auth
    
    # 使用 htpasswd 生成密码文件 (B: batch mode, b: password from command line, n: display on stdout)
    htpasswd -Bbn "$AUTH_USER" "$AUTH_PASS" > /auth/htpasswd
    
    # 设置 Registry 环境变量以使用该文件
    export REGISTRY_AUTH=htpasswd
    export REGISTRY_AUTH_HTPASSWD_REALM="Registry Realm"
    export REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd
else
    echo "⚠️ No AUTH_USER or AUTH_PASS set. Registry will be open to public (Dangerous on PaaS)."
fi

# 执行官方 Registry 的默认启动命令
# 这里的 /entrypoint.sh 是官方镜像里原本自带的脚本
exec /entrypoint.sh /etc/docker/registry/config.yml
```

### 2. 编写 Dockerfile

```dockerfile
FROM registry:2

# 安装 apache2-utils 以获得 htpasswd 工具
# 官方 registry 基于 Alpine Linux
RUN apk add --no-cache apache2-utils

# 将启动脚本复制到容器中
# ⚠️ 注意：复制为 /start.sh，绝对不要复制为 /entrypoint.sh
COPY start.sh /start.sh

# 赋予执行权限
RUN chmod +x /start.sh

# 设置自定义入口点
ENTRYPOINT ["/start.sh"]
```

---

## 🚀 部署指南 (Deploy to PaaS)

### 1. 推送代码
将上述两个文件推送到 GitHub 仓库。

### 2. 配置环境变量 (Environment Variables)
在你的 PaaS 控制台（如 Zeabur Dashboard）中，添加以下环境变量：

#### 🔐 认证配置 (必须)
| 变量名 | 示例值 | 说明 |
| :--- | :--- | :--- |
| `AUTH_USER` | `admin` | 你自定义的登录用户名 |
| `AUTH_PASS` | `SuperSecret123` | 你自定义的登录密码 |

#### ☁️ 存储配置 (强烈推荐)
**注意**：如果不配置 S3，PaaS 容器重启后，所有上传的镜像**都会丢失**。以下以 AWS S3 为例（阿里云 OSS、MinIO 等同理）：

| 变量名 | 示例值 | 说明 |
| :--- | :--- | :--- |
| `REGISTRY_STORAGE` | `s3` | 启用 S3 驱动 |
| `REGISTRY_STORAGE_S3_ACCESSKEY` | `AKIAxxxxxx` | S3 Access Key |
| `REGISTRY_STORAGE_S3_SECRETKEY` | `xxxxxx` | S3 Secret Key |
| `REGISTRY_STORAGE_S3_REGION` | `ap-northeast-1` | Bucket 所在区域 |
| `REGISTRY_STORAGE_S3_BUCKET` | `my-registry-bucket` | Bucket 名称 |

### 3. 等待部署完成
部署成功后，PaaS 平台通常会分配一个 HTTPS 域名，例如 `https://my-registry.zeabur.app`。

---

## 💻 本地使用指南

### 1. 登录仓库
```bash
docker login my-registry.zeabur.app
# 输入你在环境变量设置的 AUTH_USER 和 AUTH_PASS
```

### 2. 推送镜像
```bash
# 1. 给本地镜像打标签
docker tag nginx:latest my-registry.zeabur.app/my-nginx:v1

# 2. 推送
docker push my-registry.zeabur.app/my-nginx:v1
```

### 3. 拉取镜像
```bash
docker pull my-registry.zeabur.app/my-nginx:v1
```

---

## 🤖 CI/CD 集成 (GitHub Actions)

在其他项目的 GitHub Actions 中自动构建并推送到此仓库的配置示例：

`.github/workflows/deploy.yml`:

```yaml
name: Build and Push

on:
  push:
    branches: [ "main" ]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      # 登录到你的 PaaS 私有仓库
      - name: Login to Private Registry
        uses: docker/login-action@v3
        with:
          registry: my-registry.zeabur.app
          username: ${{ secrets.REGISTRY_USER }}  # 对应 AUTH_USER
          password: ${{ secrets.REGISTRY_PWD }}   # 对应 AUTH_PASS

      # 构建并推送
      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: my-registry.zeabur.app/my-app:latest
```

## ❓ 常见问题排查

**Q: 部署后日志一直循环输出 "Creating htpasswd..."？**
A: 这是因为 `Dockerfile` 中错误地覆盖了 `/entrypoint.sh`。请确保 `COPY start.sh /start.sh` 且 `ENTRYPOINT ["/start.sh"]` 配置正确。

**Q: 镜像上传成功，但重启服务后镜像没了？**
A: PaaS 的文件系统是临时的。请务必配置 `REGISTRY_STORAGE` 相关的环境变量，将镜像存储到 S3/OSS 中。

**Q: 需要配置 `insecure-registries` 吗？**
A: 不需要。只要你的 PaaS 平台提供了 HTTPS 域名（绝大多数都提供），Docker 客户端就可以直接安全连接。
