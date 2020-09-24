FROM alpine

RUN echo "@testing http://nl.alpinelinux.org/alpine/edge/testing" >>/etc/apk/repositories \
 && echo "@edgecommunity http://nl.alpinelinux.org/alpine/edge/community" >>/etc/apk/repositories \
 && apk add --update-cache --no-cache \
        bash \
        curl \
        jq \
        kubectl@testing \
        yq@edgecommunity

COPY . /opt/traefik-dns/
WORKDIR /opt/traefik-dns
ENTRYPOINT [ "bash", "traefik-dns.sh" ]