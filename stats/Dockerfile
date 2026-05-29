FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/lib

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    coreutils \
    ca-certificates \
    git \
    build-essential \
    sudo \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Descargar e instalar WiringOP dentro del contenedor
RUN git clone --depth 1 https://github.com/orangepi-xunlong/wiringOP.git /tmp/wiringOP \
    && cd /tmp/wiringOP \
    && ./build clean || true \
    && ./build \
    && ldconfig

COPY stats/temp_monitor.sh /app/temp_monitor.sh
COPY stats/healthcheck.sh /app/healthcheck.sh
COPY DHT22/ /app/DHT22/

RUN chmod +x /app/temp_monitor.sh /app/healthcheck.sh \
    && chmod +x /app/DHT22/dht22.out

ENTRYPOINT ["/app/temp_monitor.sh"]
