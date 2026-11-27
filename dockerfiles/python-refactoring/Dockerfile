# Python refactoring MCP server (mcp/mcp-python-refactoring, stdio,
# python:slim based - no node), bridged to streamable HTTP via
# supergateway. Node/npm installed via apt (Debian's own packages, not a
# multi-stage copy from a node image - copying just the node/npm binaries
# leaves npm's symlink-relative `require('../lib/cli.js')` unable to
# resolve, confirmed by a live CI build failure).
FROM mcp/mcp-python-refactoring:latest

RUN apt-get update && apt-get install -y --no-install-recommends nodejs npm \
    && rm -rf /var/lib/apt/lists/*
RUN npm install -g supergateway@3 && npm cache clean --force

# Chart forces runAsUser/runAsGroup 10001 regardless of this image's own
# user, so files just need to be owned by that uid, not any named user.
RUN chown -R 10001:10001 /app

EXPOSE 8080
# Upstream's own ENTRYPOINT (python-refactor server) must be cleared, or
# this CMD becomes its arguments instead of replacing it.
ENTRYPOINT []
CMD ["supergateway", \
     "--stdio", "python-refactor server", \
     "--outputTransport", "streamableHttp", \
     "--port", "8080", \
     "--healthEndpoint", "/healthz"]
