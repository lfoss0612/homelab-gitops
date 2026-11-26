# Google Workspace MCP server (workspace-mcp, by taylorwilsdon) serving Gmail,
# Calendar and Drive over native streamable HTTP on :8000 (endpoint /mcp).
# Requires env at runtime: GOOGLE_OAUTH_CLIENT_ID, GOOGLE_OAUTH_CLIENT_SECRET
FROM python:3.12-slim

RUN pip install --no-cache-dir workspace-mcp==2.7.0

RUN useradd --system --uid 10001 --create-home mcp
USER mcp
WORKDIR /home/mcp

ENV WORKSPACE_MCP_PORT=8000 \
    WORKSPACE_MCP_BASE_URI=http://0.0.0.0

EXPOSE 8000
CMD ["workspace-mcp", "--transport", "streamable-http", \
     "--tools", "gmail", "calendar", "drive", "--tool-tier", "core"]
