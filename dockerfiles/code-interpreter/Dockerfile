# Code interpreter MCP server (mcp/mcp-code-interpreter, stdio,
# python:slim/Debian based - no node), bridged to streamable HTTP via
# supergateway. Node/npm copied from node:22-slim (glibc, matches this
# Debian base).
#
# Upstream's server.py does `notebooks_folder.mkdir(exist_ok=True)` under
# /app at startup, which fails under this chart's forced non-root uid
# 10001 unless /app is writable by that uid - fixed below.
FROM node:22-slim AS nodejs

FROM mcp/mcp-code-interpreter:latest

COPY --from=nodejs /usr/local/bin/node /usr/local/bin/node
COPY --from=nodejs /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=nodejs /usr/local/bin/npm /usr/local/bin/npm
COPY --from=nodejs /usr/local/bin/npx /usr/local/bin/npx

RUN npm install -g supergateway@3 && npm cache clean --force

RUN mkdir -p /app/notebooks && chown -R 10001:10001 /app

EXPOSE 8080
CMD ["supergateway", \
     "--stdio", "python server.py", \
     "--outputTransport", "streamableHttp", \
     "--port", "8080", \
     "--healthEndpoint", "/healthz"]
