FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    sox \
    libsox-fmt-alsa \
    alsa-utils \
    ca-certificates \
    bash \
    coreutils \
    procps \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY recorder/record.sh /app/record.sh
COPY recorder/entrypoint.sh /app/entrypoint.sh
COPY recorder/healthcheck.sh /app/healthcheck.sh

# Binario de espectrograma
COPY spectrogram/ /app/spectrogram/

RUN chmod +x /app/record.sh /app/entrypoint.sh /app/healthcheck.sh \
    && chmod +x /app/spectrogram/spectrogram

ENTRYPOINT ["/app/entrypoint.sh"]
