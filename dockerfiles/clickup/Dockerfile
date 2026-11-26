# ClickUp MCP server (@nazruden/clickup-server, MIT, free - not the
# taazkareem package, which went proprietary/paid behind a license key)
# bridged to streamable HTTP via supergateway.
# Requires env at runtime: CLICKUP_PERSONAL_TOKEN
FROM node:22-alpine

RUN npm install --global supergateway@3 @nazruden/clickup-server@1.1.5 \
    && npm cache clean --force

RUN addgroup -S mcp && adduser -S -u 10001 -G mcp mcp
USER mcp
WORKDIR /home/mcp

EXPOSE 8080
CMD ["supergateway", \
     "--stdio", "clickup-server", \
     "--outputTransport", "streamableHttp", \
     "--port", "8080", \
     "--healthEndpoint", "/healthz"]
