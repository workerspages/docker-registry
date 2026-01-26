

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
          registry: docker-hub.zeabur.app
          username: ${{ secrets.REGISTRY_USER }}  # 对应 AUTH_USER
          password: ${{ secrets.REGISTRY_PWD }}   # 对应 AUTH_PASS

      # 构建并推送
      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: docker-hub.zeabur.app/镜像名:latest
```


### 接下来你可以做什么？

#### 1. 获取公网域名
在 Zeabur 的控制台里，找到这个服务的 **Networking (网络)** 或 **Domains (域名)** 设置，绑定一个域名（或者使用 Zeabur 提供的自动域名），比如 `docker-hub.zeabur.app`。

#### 2. 本地验证登录
在你的电脑终端里运行：
```bash
docker login docker-hub.zeabur.app
```
*   **Username**: `admin`
*   **Password**: *(你设置的 AUTH_PASS 密码)*

如果显示 `Login Succeeded`，那就大功告成了！

#### 3. (可选) 消除那个 Warning
日志里有一行黄色的警告：
`msg="No HTTP secret provided - generated random secret..."`
这不会影响使用，但如果你想消除它（或者为了更安全），可以在 Zeabur 的环境变量里再加一项：
*   **变量名**: `REGISTRY_HTTP_SECRET`
*   **值**: 随便生成一串乱码（比如 `a1b2c3d4e5`）



---

### 关于那个 WARNING
```text
WARNING! Your credentials are stored unencrypted in '/root/.docker/config.json'.
```
**请完全放心，这很正常。**
*   **含义**：这只是 Docker 客户端提示你，它把你的账号密码（base64编码后）保存在了本地的 `/root/.docker/config.json` 文件里，而没有使用 Linux 的系统密钥环（keychain）来加密存储。
*   **影响**：对功能没有任何影响。在服务器或 NAS 环境（看你的主机名是 `winnas`）下，这是标准表现。

---

### 🔥 趁热打铁：马上测试上传镜像

现在你已经登录成功，建议马上做一个“上传测试”，确保推送功能也正常。

#### 1. 找个小镜像练手（比如 busybox 或 nginx）
```bash
# 拉取一个公网的小镜像
docker pull busybox
```

#### 2. 给镜像打上你私有仓库的标签
**关键一步**：必须把名字改成 `你的域名/镜像名:标签` 的格式。
```bash
docker tag busybox docker-hub.zeabur.app/my-busybox:v1
```

#### 3. 推送到你的私有仓库
```bash
docker push docker-hub.zeabur.app/my-busybox:v1
```
*   如果看到进度条跑完，显示 `Pushed`，那就是完美成功！

#### 4. (可选) 验证镜像真的在里面
你可以通过 API 查看仓库里的镜像列表（需要输入密码）：
```bash
curl -u admin:你的密码 https://docker-hub.zeabur.app/v2/_catalog
```
*   成功的话应该返回：`{"repositories":["my-busybox"]}`

---

### ⚠️ 最后一次重要提醒：持久化
如果在刚才的测试中，你推送到 Zeabur 成功了，但你**还没有配置 S3/OSS 对象存储的环境变量**：
*   **现状**：镜像现在是存在 Zeabur 容器的临时硬盘里的。
*   **风险**：一旦 Zeabur 重新部署或容器重启，**你刚才上传的镜像就会消失**。

如果你已经配置好了 `REGISTRY_STORAGE_S3_...` 系列变量，那就放心使用吧！你的私人 Docker Hub 已经就绪！🚀





---

### 🚀 下一步：如何使用这个镜像？

现在，你在任何一台联网的服务器（或者你的另一台 NAS）上，都可以直接拉取这个镜像了。

**拉取命令：**
```bash
docker pull docker-hub.zeabur.app/cookiecloud:cookiecloud-metube-direct-server
```

**或者在 docker-compose.yml 中使用：**
```yaml
services:
  cookiecloud:
    image: docker-hub.zeabur.app/cookiecloud:cookiecloud-metube-direct-server
    restart: always
    # ... 其他配置
```
*(注意：在拉取之前，别忘了在那台新机器上也先执行 `docker login docker-hub.zeabur.app`)*








## ❓ 常见问题排查

**Q: 部署后日志一直循环输出 "Creating htpasswd..."？**
A: 这是因为 `Dockerfile` 中错误地覆盖了 `/entrypoint.sh`。请确保 `COPY start.sh /start.sh` 且 `ENTRYPOINT ["/start.sh"]` 配置正确。

**Q: 镜像上传成功，但重启服务后镜像没了？**
A: PaaS 的文件系统是临时的。请务必配置 `REGISTRY_STORAGE` 相关的环境变量，将镜像存储到 S3/OSS 中。

**Q: 需要配置 `insecure-registries` 吗？**
A: 不需要。只要你的 PaaS 平台提供了 HTTPS 域名（绝大多数都提供），Docker 客户端就可以直接安全连接。












### 案例

### 核心修改点：
1.  **新增登录步骤**：添加了登录你私人仓库的步骤。
2.  **修改元数据生成**：在 `docker/metadata-action` 的 `images` 列表中加入了私人仓库地址，这样 Docker 会自动为私人仓库生成同样的标签（比如 `v1.0`, `latest`, `PaaS` 等）。

### 前置准备（必须做）：
你需要去 GitHub 仓库的 **Settings -> Secrets and variables -> Actions** 中添加以下三个变量：
*   `PRIVATE_REGISTRY_HOST`: 你的私人仓库域名 (例如: `docker-hub.zeabur.app`)
*   `PRIVATE_REGISTRY_USER`: 你的用户名 (例如: `admin`)
*   `PRIVATE_REGISTRY_PWD`: 你的密码 (之前生成的那个)

---

### 修改后的 Workflow YAML

```yaml
name: Build and Push Docker Image

on:
  push:
    branches: [ PaaS ]
    tags: [ "v*" ]
  workflow_dispatch: {}

env:
  IMAGE_NAME: automation-aio

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4

      - uses: docker/setup-qemu-action@v3
      - uses: docker/setup-buildx-action@v3

      # 1. 登录 GHCR
      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.repository_owner }}
          password: ${{ secrets.GITHUB_TOKEN }}

      # 2. 登录 Docker Hub
      - name: Login to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      # 3. 登录 私人仓库 (新增步骤)
      - name: Login to Private Registry
        uses: docker/login-action@v3
        with:
          # 填你的域名，如 docker-hub.zeabur.app
          registry: ${{ secrets.PRIVATE_REGISTRY_HOST }}
          username: ${{ secrets.PRIVATE_REGISTRY_USER }}
          password: ${{ secrets.PRIVATE_REGISTRY_PWD }}

      # 4. 生成 Tags (关键修改)
      - name: Extract meta
        id: meta
        uses: docker/metadata-action@v5
        with:
          # 在这里把你的私人仓库地址加进去
          images: |
            ghcr.io/${{ github.repository_owner }}/${{ env.IMAGE_NAME }}
            docker.io/${{ secrets.DOCKERHUB_USERNAME }}/${{ env.IMAGE_NAME }}
            ${{ secrets.PRIVATE_REGISTRY_HOST }}/${{ env.IMAGE_NAME }}
          tags: |
            type=ref,event=branch
            type=ref,event=tag
            type=raw,value=latest,enable=${{ github.ref_name == github.event.repository.default_branch }}

      # 5. 构建并推送
      # 这里不需要改动，因为 tags 已经包含了上面生成的三份地址
      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: .
          file: ./Dockerfile
          push: true
          platforms: linux/amd64,linux/arm64
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
          no-cache: true
```

### 解释：为什么不需要在 `Build and push` 步骤里改 tags？

`docker/metadata-action` 这个插件非常智能。当你在它的 `images` 列表里写了三个不同的仓库地址时：
1.  GHCR
2.  Docker Hub
3.  Private Registry

它生成的 `steps.meta.outputs.tags` 输出会自动包含这三个仓库的所有标签组合。例如：
*   `ghcr.io/user/image:v1`
*   `docker.io/user/image:v1`
*   `docker-hub.zeabur.app/image:v1`

`docker/build-push-action` 读取到这个列表后，就会**一次构建，同时推送到这三个地方**。这是最高效的做法，不需要重复构建。











