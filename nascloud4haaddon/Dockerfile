ARG BUILD_FROM=ghcr.io/home-assistant/{arch}-base:3.18
FROM $BUILD_FROM

RUN apk add --no-cache \
    bash \
    curl \
    iptables \
    iproute2 \
    jq \
    wireguard-tools \
    wireguard-go \
    ca-certificates

WORKDIR /data

COPY opt/cloud /opt/haos
RUN chmod 0755 /opt/haos && chmod +x /opt/haos/cloud.sh

COPY run.sh /
RUN chmod +x /run.sh

CMD [ "/run.sh" ]
