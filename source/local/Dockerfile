FROM alpine as hans_build
RUN apk update && apk add --virtual BUILD g++ linux-headers git make libstdc++ libgcc && \
    git clone https://github.com/friedrich/hans.git && \
    cd /hans && make && chmod a+x /hans/hans && \
    apk del BUILD

FROM alpine as ptunnel_build
COPY source /build
WORKDIR /build
RUN apk update && \
    apk add --no-cache libpcap libstdc++ libgcc && \
    apk add --no-cache --virtual BUILD linux-headers libpcap-dev build-base && \
    cd tunnel && make && make install && \
    apk del BUILD

FROM alpine
COPY --from=hans_build /hans/hans /bin/hans
COPY --from=ptunnel_build /usr/bin/ptunnel /usr/bin/ptunnel
COPY --from=ptunnel_build /build/local/run.sh /run.sh
RUN apk update && \
    apk add --no-cache libpcap libstdc++ libgcc && \
    rm -rf /build /var/cache/apk/* /etc/apk/repositories && \
    chmod a+x /run.sh
ENV IP=127.0.0.1 MIDDLE_PORT=8000 SSH_PORT=22 PASSWORD=pasword
CMD ["/run.sh"]
