# Proxmox MCP server (mcp/proxmox, stdio, python:slim/Debian based - no
# node), bridged to streamable HTTP via supergateway. Node/npm copied from
# node:22-slim (glibc, matches this Debian base). Upstream ends on
# "USER mcp" - switch back to root to install, then fix ownership for this
# chart's forced runAsUser 10001 (not that image's own "mcp" uid).
FROM node:22-slim AS nodejs

FROM mcp/proxmox:latest

USER root
COPY --from=nodejs /usr/local/bin/node /usr/local/bin/node
COPY --from=nodejs /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=nodejs /usr/local/bin/npm /usr/local/bin/npm
COPY --from=nodejs /usr/local/bin/npx /usr/local/bin/npx

RUN npm install -g supergateway@3 && npm cache clean --force

RUN chown -R 10001:10001 /usr/local

EXPOSE 8080
CMD ["supergateway", \
     "--stdio", "proxmox-mcp-server", \
     "--outputTransport", "streamableHttp", \
     "--port", "8080", \
     "--healthEndpoint", "/healthz"]
