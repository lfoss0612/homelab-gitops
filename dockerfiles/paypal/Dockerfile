# PayPal MCP server (@paypal/mcp) bridged to streamable HTTP via supergateway.
# Requires env at runtime: PAYPAL_ACCESS_TOKEN, PAYPAL_ENVIRONMENT (SANDBOX|PRODUCTION)
FROM node:22-alpine

RUN npm install --global supergateway@3 @paypal/mcp@1.8.1 \
    && npm cache clean --force

RUN addgroup -S mcp && adduser -S -u 10001 -G mcp mcp
USER mcp
WORKDIR /home/mcp

EXPOSE 8080
CMD ["supergateway", \
     "--stdio", "mcp --tools=all", \
     "--outputTransport", "streamableHttp", \
     "--port", "8080", \
     "--healthEndpoint", "/healthz"]
