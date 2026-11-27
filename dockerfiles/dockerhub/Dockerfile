# Docker's official Docker Hub MCP server (mcp/dockerhub, stdio,
# node:alpine based), bridged to streamable HTTP via supergateway. The
# upstream image already switches to a non-root "appuser" - switch back to
# root to install supergateway, then fix ownership for this chart's forced
# runAsUser 10001 (not appuser's own uid).
FROM mcp/dockerhub:latest

USER root
RUN npm install -g supergateway@3 && npm cache clean --force
RUN chown -R 10001:10001 /app

EXPOSE 8080
CMD ["supergateway", \
     "--stdio", "node dist/index.js", \
     "--outputTransport", "streamableHttp", \
     "--port", "8080", \
     "--healthEndpoint", "/healthz"]
