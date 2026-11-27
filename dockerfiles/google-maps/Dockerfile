# Official modelcontextprotocol/servers Google Maps server (mcp/google-maps,
# stdio, node:22-alpine based), bridged to streamable HTTP via supergateway.
# Base image already has node+npm.
FROM mcp/google-maps:latest

RUN npm install -g supergateway@3 && npm cache clean --force

# Chart forces runAsUser/runAsGroup 10001 regardless of this image's own
# user, so files just need to be owned by that uid, not any named user.
RUN chown -R 10001:10001 /app

EXPOSE 8080
CMD ["supergateway", \
     "--stdio", "node dist/index.js", \
     "--outputTransport", "streamableHttp", \
     "--port", "8080", \
     "--healthEndpoint", "/healthz"]
