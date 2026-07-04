# Argo CD MCP server (argocd-mcp, by Akuity) bridged to streamable HTTP via
# supergateway.
# Requires env at runtime: ARGOCD_BASE_URL, ARGOCD_API_TOKEN
FROM node:22-alpine

RUN npm install --global supergateway@3 argocd-mcp@0.8.0 \
    && npm cache clean --force

RUN addgroup -S mcp && adduser -S -u 10001 -G mcp mcp
USER mcp
WORKDIR /home/mcp

EXPOSE 8080
CMD ["supergateway", \
     "--stdio", "argocd-mcp stdio", \
     "--outputTransport", "streamableHttp", \
     "--port", "8080", \
     "--healthEndpoint", "/healthz"]
