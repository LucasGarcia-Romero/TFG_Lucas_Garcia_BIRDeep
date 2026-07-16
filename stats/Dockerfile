# syntax=docker/dockerfile:1

# WiringOP se compila aquí. Nada del compilador pasa a la imagen final.
FROM debian:bookworm-slim AS wiringop_builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates \
       gcc \
       git \
       libc6-dev \
       libcrypt-dev \
       make \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 \
      https://github.com/orangepi-xunlong/wiringOP.git \
      /tmp/wiringOP \
    && cd /tmp/wiringOP \
    && WIRINGPI_SUDO= ./build \
    && rm -rf /tmp/wiringOP


FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/lib

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       bash \
       ca-certificates \
       coreutils \
       libcrypt1 \
    && rm -rf /var/lib/apt/lists/*

# Solo pasan las bibliotecas y la utilidad gpio ya compiladas.
COPY --from=wiringop_builder /usr/local/lib/ /usr/local/lib/
COPY --from=wiringop_builder /usr/local/bin/gpio /usr/local/bin/gpio

RUN ldconfig

WORKDIR /app

COPY stats/temp_monitor.sh /app/temp_monitor.sh
COPY stats/healthcheck.sh /app/healthcheck.sh
COPY DHT22/ /app/DHT22/

RUN chmod +x \
      /app/temp_monitor.sh \
      /app/healthcheck.sh \
      /app/DHT22/dht22.out

ENTRYPOINT ["/app/temp_monitor.sh"]
