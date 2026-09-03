# Build stage: compile meilink-tunnel (embedded frp library) from source.
# Replaces the old frpc binary download — AV software frequently quarantines
# the well-known frpc binary name, while a self-built project-specific binary
# avoids hash-based and name-based signature matches.
FROM golang:1.25-alpine AS engine-builder
COPY client/desktop/sidecar/ /sidecar/
RUN cd /sidecar && CGO_ENABLED=0 go build -o /usr/local/bin/meilink-tunnel ./cmd/meilink-tunnel/

FROM node:22-alpine

# GHCR 用该 label 把 package 与源仓库绑定，确保 GITHUB_TOKEN 有 push 权限
LABEL org.opencontainers.image.source="https://github.com/tomtrije/mei-link"

WORKDIR /app
COPY --from=engine-builder /usr/local/bin/meilink-tunnel /usr/local/bin/meilink-tunnel
COPY client/docker/src ./src
COPY client/docker/web ./web
COPY client/docker/package.json ./
RUN adduser -D -u 10001 meilink && mkdir /data && chown meilink /data \
    && apk add --no-cache su-exec

COPY client/docker/docker-entrypoint.sh ./
RUN chmod +x docker-entrypoint.sh

# 注意：不设 USER meilink —— entrypoint 需以 root 启动来 chown 挂载卷，
# 随后用 su-exec 降权为 meilink 运行 node 服务。
ENV MEILINK_DATA_DIR=/data \
    MEILINK_FRPC_PATH=/usr/local/bin/meilink-tunnel \
    MEILINK_WEB_PORT=17420 \
    MEILINK_ADMIN_USER=admin \
    MEILINK_ADMIN_PASSWORD=
VOLUME ["/data"]
EXPOSE 17420
HEALTHCHECK CMD node -e "fetch('http://127.0.0.1:17420/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
ENTRYPOINT ["./docker-entrypoint.sh"]
