# OPNsense MCP server (opnsense-mcp-server, by lucamarien; stdio only) bridged
# to streamable HTTP via supergateway. Read-only unless OPNSENSE_ALLOW_WRITES=true.
# Requires env at runtime: OPNSENSE_URL, OPNSENSE_API_KEY, OPNSENSE_API_SECRET
# (optional: OPNSENSE_VERIFY_SSL, OPNSENSE_ALLOW_WRITES)
FROM node:22-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 python3-venv \
    && rm -rf /var/lib/apt/lists/* \
    && python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir opnsense-mcp-server==0.4.2 \
    && npm install --global supergateway@3 \
    && npm cache clean --force

ENV PATH=/opt/venv/bin:$PATH

RUN useradd --system --uid 10001 --create-home mcp
USER mcp
WORKDIR /home/mcp

EXPOSE 8080
CMD ["supergateway", \
     "--stdio", "opnsense-mcp", \
     "--outputTransport", "streamableHttp", \
     "--port", "8080", \
     "--healthEndpoint", "/healthz"]
