# syntax=docker/dockerfile:1

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Estas dependencias se conservan porque los scripts pueden usar arecord/amixer,
# SoX, curl, bash y las utilidades de proceso durante la ejecución.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       alsa-utils \
       bash \
       ca-certificates \
       coreutils \
       curl \
       libsox-fmt-alsa \
       procps \
       sox \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY recorder/record.sh /app/record.sh
COPY recorder/entrypoint.sh /app/entrypoint.sh
COPY recorder/healthcheck.sh /app/healthcheck.sh
COPY spectrogram/ /app/spectrogram/

RUN chmod +x \
      /app/record.sh \
      /app/entrypoint.sh \
      /app/healthcheck.sh \
      /app/spectrogram/spectrogram

ENTRYPOINT ["/app/entrypoint.sh"]
