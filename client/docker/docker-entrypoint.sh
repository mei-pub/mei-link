#!/bin/sh
set -e

echo "[entrypoint] fixing /data ownership (running as $(id))"

# 修复挂载卷的权限：容器内 node 服务以 meilink 用户运行，
# 但宿主机 bind mount 的 /data 目录通常属于 root（UID 0），
# 导致 meilink 用户无法写入。这里以 root 身份夺回 /data 的所有权。
chown -R meilink:meilink /data

echo "[entrypoint] /data now: $(ls -ld /data)"
echo "[entrypoint] dropping privileges to meilink and starting node..."

# 降权为 meilink 用户运行 Node.js 服务（su-exec 是 Alpine 的轻量降权工具）
exec su-exec meilink node --experimental-strip-types src/server.ts
