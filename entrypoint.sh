#!/bin/sh
set -e

# 如果设置了用户名和密码的环境变量，则生成密码文件
if [ -n "$AUTH_USER" ] && [ -n "$AUTH_PASS" ]; then
    echo "Creating htpasswd file for user: $AUTH_USER"
    mkdir -p /auth
    # 使用 htpasswd 生成密码文件
    htpasswd -Bbn "$AUTH_USER" "$AUTH_PASS" > /auth/htpasswd
    
    # 设置 Registry 环境变量以使用该文件
    export REGISTRY_AUTH=htpasswd
    export REGISTRY_AUTH_HTPASSWD_REALM="Registry Realm"
    export REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd
fi

# 执行官方 Registry 的默认启动命令
exec /entrypoint.sh /etc/docker/registry/config.yml
