# Finnhub MCP server (@cyanheads/finnhub-mcp-server, Apache-2.0, free)
# bridged to streamable HTTP via supergateway.
# Requires env at runtime: FINNHUB_API_KEY
#
# Free Finnhub tier is 60 req/min, for personal use only (no redistributing
# Finnhub data to third parties per Finnhub's ToS) - fine for this gateway's
# own use, not a public-facing resale of the data.
FROM node:22-alpine

RUN npm install --global supergateway@3 @cyanheads/finnhub-mcp-server@0.2.1 \
    && npm cache clean --force

RUN addgroup -S mcp && adduser -S -u 10001 -G mcp mcp
USER mcp
WORKDIR /home/mcp

EXPOSE 8080
CMD ["supergateway", \
     "--stdio", "finnhub-mcp-server", \
     "--outputTransport", "streamableHttp", \
     "--port", "8080", \
     "--healthEndpoint", "/healthz"]
