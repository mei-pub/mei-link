#!/bin/sh
set -e

# 修复挂载卷的权限：容器内以 meilink 用户运行，
# 但宿主机挂载的 /data 目录可能属于 root（UID 0），
# 导致 meilink 用户无法写入。
chown -R meilink:meilink /data

# 降权为 meilink 用户运行 Node.js 服务
exec su-exec meilink node --experimental-strip-types src/server.ts