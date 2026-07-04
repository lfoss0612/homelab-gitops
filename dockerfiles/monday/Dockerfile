# monday.com MCP server (@mondaydotcomorg/monday-api-mcp) bridged to
# streamable HTTP via supergateway.
# Requires env at runtime: MONDAY_TOKEN
FROM node:22-alpine

RUN npm install --global supergateway@3 @mondaydotcomorg/monday-api-mcp@3.3.0 \
    && npm cache clean --force

RUN addgroup -S mcp && adduser -S -u 10001 -G mcp mcp
USER mcp
WORKDIR /home/mcp

EXPOSE 8080
CMD ["sh", "-c", "exec supergateway \
     --stdio \"mcp-server-monday-api -t $MONDAY_TOKEN\" \
     --outputTransport streamableHttp \
     --port 8080 \
     --healthEndpoint /healthz"]
