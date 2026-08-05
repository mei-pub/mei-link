FROM node:22-alpine

ARG TARGETARCH
ARG FRP_VERSION=0.70.0

RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) FRP_SHA256=281cb31e6b915113179c6ebb65b5977a5d9d7fb96f9a70867be83dee3b657721 ;; \
      arm64) FRP_SHA256=9dd282fd8d1b90a8ee760702ac5b876748b519c6bdfac7c68418f62a05d805c6 ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    apk add --no-cache curl tar; \
    curl --fail --location --show-error --silent --retry 5 --retry-all-errors --retry-delay 2 -o /tmp/frp.tgz "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${TARGETARCH}.tar.gz"; \
    echo "${FRP_SHA256}  /tmp/frp.tgz" | sha256sum -c -; \
    tar -xzf /tmp/frp.tgz --strip-components=1 -C /usr/local/bin "frp_${FRP_VERSION}_linux_${TARGETARCH}/frps"; \
    rm /tmp/frp.tgz; \
    frps --version

WORKDIR /app
COPY src ./src
COPY web ./web
COPY package.json ./
RUN adduser -D -u 10001 meilink && mkdir /data && chown meilink /data \
    && apk add --no-cache su-exec

COPY docker-entrypoint.sh ./
RUN chmod +x docker-entrypoint.sh

# 注意：不设 USER meilink —— entrypoint 需以 root 启动来 chown 挂载卷，
# 随后用 su-exec 降权为 meilink 运行 node 服务。
ENV MEILINK_DATA_DIR=/data MEILINK_FRPS_PATH=/usr/local/bin/frps MEILINK_WEB_PORT=17500
VOLUME ["/data"]
EXPOSE 7000 8080 8443 17500
HEALTHCHECK CMD node -e "fetch('http://127.0.0.1:17500/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
ENTRYPOINT ["./docker-entrypoint.sh"]
