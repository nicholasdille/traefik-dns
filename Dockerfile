FROM alpine

RUN echo "@testing http://nl.alpinelinux.org/alpine/edge/testing" >>/etc/apk/repositories \
 && apk add --update-cache --no-cache \
        bash \
        curl \
        jq \
        kubectl@testing

COPY traefik-dns.sh /
ENTRYPOINT [ "bash", "/traefik-dns.sh" ]