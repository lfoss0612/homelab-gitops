# Finnhub MCP server (@cyanheads/finnhub-mcp-server, Apache-2.0, free)
# bridged to streamable HTTP via supergateway.
# Requires env at runtime: FINNHUB_API_KEY
#
# Free Finnhub tier is 60 req/min, for personal use only (no redistributing
# Finnhub data to third parties per Finnhub's ToS) - fine for this gateway's
# own use, not a public-facing resale of the data.
#
# Needs Node >=24: its @cyanheads/mcp-ts-core dependency refuses to start
# on Node 22 (the version every other wrapper here uses) - confirmed live,
# "Configuration error - server failed to start... requires Node.js >=24.0.0".
#
# supergateway's default "stateless" stdio<->streamableHttp mode spawns a
# brand-new stdio child for every single request and never reaps it -
# confirmed live on this server's proxmox/opnsense siblings, OOMKilled
# against the 512Mi limit after a handful of requests. Known upstream bug
# (supercorp-ai/supergateway#108, fixed by #187, 2026-09-16) but only in
# the 4.x line; pinning to 3 can never pick it up. Bump the pin past that
# fix AND switch to --stateful, which spawns one child per session instead
# of per request - both less leaky and far faster (no repeated cold-start
# on every call). sessionTimeout matches upstream's own stateful default
# (30min) explicitly rather than relying on it.
FROM node:24-alpine

RUN npm install --global supergateway@4 @cyanheads/finnhub-mcp-server@0.2.1 \
    && npm cache clean --force

RUN addgroup -S mcp && adduser -S -u 10001 -G mcp mcp
USER mcp
WORKDIR /home/mcp

EXPOSE 8080
CMD ["supergateway", \
     "--stdio", "finnhub-mcp-server", \
     "--outputTransport", "streamableHttp", \
     "--stateful", \
     "--sessionTimeout", "1800000", \
     "--port", "8080", \
     "--healthEndpoint", "/healthz"]
