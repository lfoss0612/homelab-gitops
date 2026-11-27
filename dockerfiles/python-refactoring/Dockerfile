# Python refactoring MCP server (mcp/mcp-python-refactoring, stdio,
# python:slim/Debian based - no node), bridged to streamable HTTP via
# supergateway. Node/npm copied from node:22-slim (glibc, matches this
# Debian base - an Alpine/musl node binary would not run here).
FROM node:22-slim AS nodejs

FROM mcp/mcp-python-refactoring:latest

COPY --from=nodejs /usr/local/bin/node /usr/local/bin/node
COPY --from=nodejs /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=nodejs /usr/local/bin/npm /usr/local/bin/npm
COPY --from=nodejs /usr/local/bin/npx /usr/local/bin/npx

RUN npm install -g supergateway@3 && npm cache clean --force

# Chart forces runAsUser/runAsGroup 10001 regardless of this image's own
# user, so files just need to be owned by that uid, not any named user.
RUN chown -R 10001:10001 /app

EXPOSE 8080
CMD ["supergateway", \
     "--stdio", "python-refactor server", \
     "--outputTransport", "streamableHttp", \
     "--port", "8080", \
     "--healthEndpoint", "/healthz"]
