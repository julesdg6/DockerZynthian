FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    coreutils \
    curl \
    fdisk \
    file \
    gawk \
    grep \
    mtools \
    qemu-system-aarch64 \
    qemu-system-arm \
    qemu-utils \
    sed \
    unzip \
    util-linux \
    xz-utils \
    gzip \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY scripts /usr/local/bin
RUN chmod +x /usr/local/bin/*.sh

VOLUME ["/data"]

EXPOSE 2222 8080 8443 6080 5900

ENTRYPOINT ["/usr/local/bin/run-qemu.sh"]
