# Official modelcontextprotocol/servers git server (mcp/git, stdio,
# python:slim-bookworm/Debian based - no node), bridged to streamable HTTP
# via supergateway. Node/npm installed via apt (Debian's own packages,
# not a multi-stage copy from a node image - copying just the node/npm
# binaries leaves npm's symlink-relative `require('../lib/cli.js')`
# unable to resolve, confirmed by a live CI build failure).
#
# Upstream's uv-built venv at /app/.venv is not executable by this chart's
# forced non-root uid 10001 as shipped ("permission denied" on
# mcp-server-git) - fixed below.
FROM mcp/git:latest

RUN apt-get update && apt-get install -y --no-install-recommends nodejs npm \
    && rm -rf /var/lib/apt/lists/*
RUN npm install -g supergateway@3 && npm cache clean --force

RUN chown -R 10001:10001 /app

EXPOSE 8080
# Upstream's own ENTRYPOINT (mcp-server-git) must be cleared, or this CMD
# becomes its arguments instead of replacing it.
ENTRYPOINT []
CMD ["supergateway", \
     "--stdio", "mcp-server-git", \
     "--outputTransport", "streamableHttp", \
     "--port", "8080", \
     "--healthEndpoint", "/healthz"]
