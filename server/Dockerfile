# syntax=docker/dockerfile:1

# Cliente Docker estático, sin daemon, containerd ni runc.
FROM docker:cli AS docker_cli

# Etapa exclusiva de compilación.
FROM debian:bookworm-slim AS server_builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       g++ \
       libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY httpserver/ /src/

RUN mkdir -p /out \
    && g++ -O2 -std=c++20 \
       mHttpServer.cpp \
       lib/HttpServer.cpp \
       lib/HttpConnection.cpp \
       lib/PostMethod.cpp \
       lib/temperature_history.cpp \
       -o /out/mHttpServer \
       -lssl -lcrypto \
    && strip /out/mHttpServer


FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates \
       libssl3 \
       libstdc++6 \
       wget \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Se mantienen todos los recursos del servidor, incluido /app/html.
COPY httpserver/ /app/
COPY server/healthcheck.sh /app/healthcheck.sh
COPY --from=server_builder /out/mHttpServer /usr/local/bin/mHttpServer

# Conserva los comandos Docker, pero no instala el daemon dentro del contenedor.
COPY --from=docker_cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker_cli /usr/local/libexec/docker/cli-plugins/ /usr/local/libexec/docker/cli-plugins/

RUN ln -sf /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose \
    && chmod +x /usr/local/bin/mHttpServer /app/healthcheck.sh

EXPOSE 8000

CMD ["/usr/local/bin/mHttpServer", "--serverPort", "8000", "--htmlFilesFolder", "/app/html", "--dataFilesFolder", "/data"]
