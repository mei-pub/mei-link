FROM node:22-alpine
ARG FRP_VERSION=0.70.0
RUN apk add --no-cache curl unzip && curl -fsSL https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz | tar -xz --strip-components=1 -C /usr/local/bin frp_${FRP_VERSION}_linux_amd64/frpc
WORKDIR /app
COPY src ./src
COPY web ./web
COPY package.json ./
RUN adduser -D -u 10001 meilink && mkdir /data && chown meilink /data
USER meilink
ENV MEILINK_DATA_DIR=/data MEILINK_FRPC_PATH=/usr/local/bin/frpc MEILINK_WEB_PORT=17420
VOLUME ["/data"]
EXPOSE 17420
HEALTHCHECK CMD node -e "fetch('http://127.0.0.1:17420/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node","--experimental-strip-types","src/server.ts"]
