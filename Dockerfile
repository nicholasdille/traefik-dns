FROM alpine

RUN apk add --update-cache --no-cache \
        bash \
        curl \
        jq \
        kubectl

COPY traefik-dns.sh /
ENTRYPOINT [ "bash", "/traefik-dns.sh" ]