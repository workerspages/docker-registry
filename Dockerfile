FROM registry:2

# 安装 htpasswd 工具
RUN apk add --no-cache apache2-utils

# ⚠️ 修改点：复制为 start.sh，而不是 entrypoint.sh
COPY start.sh /start.sh
RUN chmod +x /start.sh

# ⚠️ 修改点：入口点改为 start.sh
ENTRYPOINT ["/start.sh"]
