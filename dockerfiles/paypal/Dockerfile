# PayPal MCP server (@paypal/mcp) bridged to streamable HTTP via supergateway.
# Read-only tool subset: no create/send/pay/refund/cancel/update tools are exposed
# through LiteLLM. Widen --tools deliberately (accepted IDs: see @paypal/mcp
# dist/index.js ACCEPTED_TOOLS).
# Requires env at runtime: PAYPAL_ACCESS_TOKEN, PAYPAL_ENVIRONMENT (SANDBOX|PRODUCTION)
FROM node:22-alpine

RUN npm install --global supergateway@3 @paypal/mcp@1.8.1 \
    && npm cache clean --force

RUN addgroup -S mcp && adduser -S -u 10001 -G mcp mcp
USER mcp
WORKDIR /home/mcp

EXPOSE 8080
CMD ["supergateway", \
     "--stdio", "mcp --tools=invoices.list,invoices.get,orders.get,disputes.list,disputes.get,shipment.get,products.list,products.show,subscriptionPlans.list,subscriptionPlans.show,subscriptions.show,transactions.list,payments.getRefunds", \
     "--outputTransport", "streamableHttp", \
     "--port", "8080", \
     "--healthEndpoint", "/healthz"]
