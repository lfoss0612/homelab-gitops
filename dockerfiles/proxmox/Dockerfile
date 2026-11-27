# Proxmox MCP server (mcp/proxmox, stdio, python:slim/Debian based - no
# node), bridged to streamable HTTP via supergateway. Node/npm installed
# via apt (Debian's own packages, not a multi-stage copy from a node image
# - copying just the node/npm binaries leaves npm's symlink-relative
# `require('../lib/cli.js')` unable to resolve, confirmed by a live CI
# build failure). Upstream ends on "USER mcp" - switch back to root to
# install, then fix ownership for this chart's forced runAsUser 10001
# (not that image's own "mcp" uid).
FROM mcp/proxmox:latest

USER root
RUN apt-get update && apt-get install -y --no-install-recommends nodejs npm \
    && rm -rf /var/lib/apt/lists/*
RUN npm install -g supergateway@3 && npm cache clean --force

RUN chown -R 10001:10001 /usr/local

EXPOSE 8080
# Upstream's own ENTRYPOINT (proxmox-mcp-server) must be cleared, or this
# CMD becomes its arguments instead of replacing it.
ENTRYPOINT []
CMD ["supergateway", \
     "--stdio", "proxmox-mcp-server", \
     "--outputTransport", "streamableHttp", \
     "--port", "8080", \
     "--healthEndpoint", "/healthz"]
