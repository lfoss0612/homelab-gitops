# Code interpreter MCP server (mcp/mcp-code-interpreter, stdio,
# python:slim based - no node), bridged to streamable HTTP via
# supergateway. Node/npm installed via apt (Debian's own packages, not a
# multi-stage copy from a node image - copying just the node/npm binaries
# leaves npm's symlink-relative `require('../lib/cli.js')` unable to
# resolve, confirmed by a live CI build failure).
#
# Upstream's server.py does `notebooks_folder.mkdir(exist_ok=True)` under
# /app at startup, which fails under this chart's forced non-root uid
# 10001 unless /app is writable by that uid - fixed below.
FROM mcp/mcp-code-interpreter:latest

RUN apt-get update && apt-get install -y --no-install-recommends nodejs npm \
    && rm -rf /var/lib/apt/lists/*
RUN npm install -g supergateway@3 && npm cache clean --force

RUN mkdir -p /app/notebooks && chown -R 10001:10001 /app

EXPOSE 8080
CMD ["supergateway", \
     "--stdio", "python server.py", \
     "--outputTransport", "streamableHttp", \
     "--port", "8080", \
     "--healthEndpoint", "/healthz"]
