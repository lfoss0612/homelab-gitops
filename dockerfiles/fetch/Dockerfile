# Official MCP fetch server (mcp-server-fetch, modelcontextprotocol/servers;
# stdio only) bridged to streamable HTTP via supergateway. By default it
# refuses private, loopback and link-local addresses (incl. cloud metadata),
# which keeps it from being used to reach in-cluster or LAN services. Do NOT
# add --allow-private-ips.
FROM node:22-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 python3-venv \
    && rm -rf /var/lib/apt/lists/* \
    && python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir mcp-server-fetch==2026.11.11 \
    && npm install --global supergateway@3 \
    && npm cache clean --force

ENV PATH=/opt/venv/bin:$PATH

RUN useradd --system --uid 10001 --create-home mcp
USER mcp
WORKDIR /home/mcp

EXPOSE 8080
CMD ["supergateway", \
     "--stdio", "mcp-server-fetch", \
     "--outputTransport", "streamableHttp", \
     "--port", "8080", \
     "--healthEndpoint", "/healthz"]
