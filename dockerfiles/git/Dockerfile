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
#
# This base is Debian bookworm, whose own apt nodejs package is 18.x -
# too old for supergateway/the MCP SDK's use of the global WebCrypto API
# (stable only from Node 19+), confirmed live ("ReferenceError: crypto is
# not defined"). NodeSource's setup script gets a current LTS instead,
# same fix this fleet already uses elsewhere for the same Debian-nodejs-
# too-old problem (see homelab-ansible's nodesource-repo.yml bootstrap).
FROM mcp/git:latest

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
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
