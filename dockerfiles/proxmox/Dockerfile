# Proxmox MCP server (mcp/proxmox, stdio, python:slim/Debian based - no
# node), bridged to streamable HTTP via supergateway. Node/npm installed
# via apt (Debian's own packages, not a multi-stage copy from a node image
# - copying just the node/npm binaries leaves npm's symlink-relative
# `require('../lib/cli.js')` unable to resolve, confirmed by a live CI
# build failure). Upstream ends on "USER mcp" - switch back to root to
# install, then fix ownership for this chart's forced runAsUser 10001
# (not that image's own "mcp" uid).
#
# supergateway's default "stateless" stdio<->streamableHttp mode spawns a
# brand-new stdio child (a whole fresh Python/FastMCP interpreter here) for
# every single request and never reaps it - confirmed live, 10 bare
# `initialize` calls OOMKilled this pod against its 512Mi limit. This is a
# known upstream bug (supercorp-ai/supergateway#108, fixed by #187,
# 2026-09-16) but only in the 4.x line; pinning to 3 can never pick it up.
# Bump the pin past that fix AND switch to --stateful, which spawns one
# child per session instead of per request - both less leaky and far
# faster (no repeated interpreter cold-start on every call). sessionTimeout
# matches upstream's own stateful default (30min) explicitly rather than
# relying on it.
FROM mcp/proxmox:latest

USER root
RUN apt-get update && apt-get install -y --no-install-recommends nodejs npm \
    && rm -rf /var/lib/apt/lists/*
RUN npm install -g supergateway@4 && npm cache clean --force

RUN chown -R 10001:10001 /usr/local

EXPOSE 8080
# Upstream's own ENTRYPOINT (proxmox-mcp-server) must be cleared, or this
# CMD becomes its arguments instead of replacing it.
ENTRYPOINT []
CMD ["supergateway", \
     "--stdio", "proxmox-mcp-server", \
     "--outputTransport", "streamableHttp", \
     "--stateful", \
     "--sessionTimeout", "1800000", \
     "--port", "8080", \
     "--healthEndpoint", "/healthz"]
