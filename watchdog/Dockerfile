# syntax=docker/dockerfile:1

# Tomamos únicamente el cliente Docker y sus plugins oficiales.
FROM docker:cli AS docker_cli

FROM alpine:3.24

RUN apk add --no-cache \
    bash \
    ca-certificates \
    coreutils \
    findutils \
    gawk \
    procps

# No copiamos dockerd, containerd ni runc: el watchdog usa el socket del host.
COPY --from=docker_cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker_cli /usr/local/libexec/docker/cli-plugins/ /usr/local/libexec/docker/cli-plugins/

# Conserva compatibilidad tanto con "docker compose" como con "docker-compose".
RUN ln -sf /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose

COPY watchdog/watchdog.sh /usr/local/bin/recorder-watchdog
RUN chmod +x /usr/local/bin/recorder-watchdog

CMD ["/usr/local/bin/recorder-watchdog"]
