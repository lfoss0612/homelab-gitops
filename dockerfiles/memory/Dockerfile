# Reference knowledge-graph memory server (mcp/memory, stdio), bridged to
# streamable HTTP via supergateway. Base image already has node+npm, so
# supergateway installs straight on top - no cross-base node copy needed.
FROM mcp/memory:latest

RUN npm install -g supergateway@3 && npm cache clean --force

# Chart forces runAsUser/runAsGroup 10001 regardless of this image's own
# user, so files just need to be owned by that uid, not any named user.
RUN chown -R 10001:10001 /app

EXPOSE 8080
# Upstream's own ENTRYPOINT (node dist/index.js) must be cleared, or this
# CMD becomes its arguments instead of replacing it - confirmed live: the
# pod ran the memory server directly on stdio with no supergateway at all.
ENTRYPOINT []
CMD ["supergateway", \
     "--stdio", "node dist/index.js", \
     "--outputTransport", "streamableHttp", \
     "--port", "8080", \
     "--healthEndpoint", "/healthz"]
