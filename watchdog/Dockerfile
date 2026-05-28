FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    docker.io \
    coreutils \
    findutils \
    gawk \
    procps \
    && rm -rf /var/lib/apt/lists/*

COPY watchdog/watchdog.sh /usr/local/bin/recorder-watchdog
RUN chmod +x /usr/local/bin/recorder-watchdog

CMD ["/usr/local/bin/recorder-watchdog"]
