FROM registry:2

# 安装 apache2-utils 以获得 htpasswd 工具
# 官方 registry 基于 Alpine Linux
RUN apk add --no-cache apache2-utils

# 复制启动脚本
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 设置入口点
ENTRYPOINT ["/entrypoint.sh"]
