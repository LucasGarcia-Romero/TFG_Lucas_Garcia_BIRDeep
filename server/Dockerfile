FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    g++ \
    make \
    ca-certificates \
    docker.io \
    wget \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Codigo del servidor
COPY httpserver/ /app/
COPY server/healthcheck.sh /app/healthcheck.sh

# Compilar el binario
RUN g++ -O2 -std=c++20 \
    mHttpServer.cpp \
    lib/HttpServer.cpp \
    lib/HttpConnection.cpp \
    lib/PostMethod.cpp \
    lib/temperature_history.cpp \
    -o /usr/local/bin/mHttpServer \
    -lssl -lcrypto \
    && chmod +x /app/healthcheck.sh

EXPOSE 8000

CMD ["/usr/local/bin/mHttpServer", "--serverPort", "8000", "--htmlFilesFolder", "/app/html", "--dataFilesFolder", "/data"]
