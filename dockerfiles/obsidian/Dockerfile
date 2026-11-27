# Docker's official Obsidian MCP server (mcp/obsidian, stdio,
# python:slim-bookworm/Debian based - no node), bridged to streamable HTTP
# via supergateway. Node/npm installed via apt (Debian's own packages,
# not a multi-stage copy from a node image - copying just the node/npm
# binaries leaves npm's symlink-relative `require('../lib/cli.js')`
# unable to resolve, confirmed by a live CI build failure).
#
# Same uv-built /app/.venv layout as mcp/git - proactively fixing
# permissions for this chart's forced non-root uid 10001 to avoid the same
# "permission denied" that hit the git wrapper.
FROM mcp/obsidian:latest

RUN apt-get update && apt-get install -y --no-install-recommends nodejs npm \
    && rm -rf /var/lib/apt/lists/*
RUN npm install -g supergateway@3 && npm cache clean --force

RUN chown -R 10001:10001 /app

EXPOSE 8080
# Upstream's own ENTRYPOINT (mcp-obsidian) must be cleared, or this CMD
# becomes its arguments instead of replacing it.
ENTRYPOINT []
CMD ["supergateway", \
     "--stdio", "mcp-obsidian", \
     "--outputTransport", "streamableHttp", \
     "--port", "8080", \
     "--healthEndpoint", "/healthz"]
