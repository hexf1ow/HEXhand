# HEXhand — container runtime, built from the local source tree (commit 5d11c36)
FROM ubuntu:24.04

RUN apt-get update \
 && apt-get install -y --no-install-recommends socat ca-certificates tmux \
 && rm -rf /var/lib/apt/lists/*

COPY target/release/hexhand /usr/local/bin/hexhand
COPY deploy/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENV PORT=3200 \
    WORKSPACE_ROOT=/workspace \
    TERM=xterm-256color \
    HOME=/root

WORKDIR /workspace
EXPOSE 3201
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
