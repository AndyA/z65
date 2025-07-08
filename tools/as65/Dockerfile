FROM debian:bookworm-slim
LABEL "maintainer"="Andy Armstrong <andy@hexten.net>"

COPY as65 /usr/local/bin/as65

RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install --yes --no-install-recommends \
      libc6:i386 libstdc++6:i386 \
      file findutils && \
    apt-get -y autoremove && \
    apt-get clean autoclean && \
    rm -rf /tmp/* /var/tmp/* /var/lib/apt/lists

ENTRYPOINT ["as65"]