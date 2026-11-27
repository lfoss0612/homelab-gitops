# Docker's official Obsidian MCP server (mcp/obsidian, stdio,
# python:slim-bookworm/Debian based - no node), bridged to streamable HTTP
# via supergateway. Node/npm copied from node:22-slim (glibc, matches this
# Debian base).
#
# Same uv-built /app/.venv layout as mcp/git - proactively fixing
# permissions for this chart's forced non-root uid 10001 to avoid the same
# "permission denied" that hit the git wrapper.
FROM node:22-slim AS nodejs

FROM mcp/obsidian:latest

COPY --from=nodejs /usr/local/bin/node /usr/local/bin/node
COPY --from=nodejs /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=nodejs /usr/local/bin/npm /usr/local/bin/npm
COPY --from=nodejs /usr/local/bin/npx /usr/local/bin/npx

RUN npm install -g supergateway@3 && npm cache clean --force

RUN chown -R 10001:10001 /app

EXPOSE 8080
CMD ["supergateway", \
     "--stdio", "mcp-obsidian", \
     "--outputTransport", "streamableHttp", \
     "--port", "8080", \
     "--healthEndpoint", "/healthz"]
