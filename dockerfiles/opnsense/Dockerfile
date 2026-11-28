# OPNsense MCP server (opnsense-mcp-server, by lucamarien; stdio only) bridged
# to streamable HTTP via supergateway. Read-only unless OPNSENSE_ALLOW_WRITES=true.
# Requires env at runtime: OPNSENSE_URL, OPNSENSE_API_KEY, OPNSENSE_API_SECRET
# (optional: OPNSENSE_VERIFY_SSL, OPNSENSE_ALLOW_WRITES)
#
# supergateway's default "stateless" stdio<->streamableHttp mode spawns a
# brand-new stdio child (a whole fresh Python/FastMCP interpreter here) for
# every single request and never reaps it - confirmed live, a handful of
# bare `initialize` calls OOMKilled this pod against its 512Mi limit. This
# is a known upstream bug (supercorp-ai/supergateway#108, fixed by #187,
# 2026-09-16) but only in the 4.x line; pinning to 3 can never pick it up.
# Bump the pin past that fix AND switch to --stateful, which spawns one
# child per session instead of per request - both less leaky and far
# faster (no repeated interpreter cold-start on every call). sessionTimeout
# matches upstream's own stateful default (30min) explicitly rather than
# relying on it.
FROM node:22-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 python3-venv \
    && rm -rf /var/lib/apt/lists/* \
    && python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir opnsense-mcp-server==0.4.2 \
    && npm install --global supergateway@4 \
    && npm cache clean --force

ENV PATH=/opt/venv/bin:$PATH

RUN useradd --system --uid 10001 --create-home mcp
USER mcp
WORKDIR /home/mcp

EXPOSE 8080
CMD ["supergateway", \
     "--stdio", "opnsense-mcp", \
     "--outputTransport", "streamableHttp", \
     "--stateful", \
     "--sessionTimeout", "1800000", \
     "--port", "8080", \
     "--healthEndpoint", "/healthz"]
