# homelab-gitops

GitOps repository for the homelab Kubernetes cluster, managed by Argo CD with a
nested app-of-apps pattern. Two trees:

- **platform** — the pre-existing cluster apps (cert-manager, longhorn,
  rancher, gpu-operator, yugabyte, ...), exported from the live Argo CD and
  organized **by namespace**. A root `platform` app-of-apps creates one
  `platform-<namespace>` app-of-apps per cluster namespace, and each of those
  syncs the workload Applications in `argocd/<namespace>/`.
- **mcp-servers** — one Argo CD Application per MCP server, all instantiating a
  single reusable Helm chart, managed by the `mcp-servers` app-of-apps.

See [docs/architecture.md](docs/architecture.md) for a visual diagram of the
app-of-apps trees and the wrapper → workload mapping.

## Structure

```
argocd/
  platform-app.yaml        # root app-of-apps: syncs argocd/platform-apps/
  platform-apps/           # one app-of-apps per namespace, + AppProjects
    projects.yaml          # add-ons, ai, system, yugabyte AppProjects
    <namespace>.yaml       # app platform-<namespace> -> syncs argocd/<namespace>/
  <namespace>/             # one dir per cluster namespace, holds its workloads
    <app>.yaml             # e.g. yugabytedb/{yugabyte,pgadmin}.yaml
  pending/                 # NOT synced: apps whose specs contain credentials
  root-app.yaml            # app-of-apps: syncs everything under argocd/apps/
  apps/mcp-<name>.yaml     # one Argo CD Application per server
charts/mcp-server/         # reusable single-server Helm chart
  values.yaml              # hardened defaults (security context, resources, ...)
  values/<name>.yaml       # per-server overrides (image, port, secrets, ingress)
  templates/               # Deployment, Service, Ingress, Secret, ServiceAccount
dockerfiles/
  paypal/  clickup/  argocd/  finnhub/  ...  # pinned wrapper Dockerfiles (stdio -> HTTP)
  Dockerfile.npm-wrapper      # generic wrapper for experimenting with new servers
.github/workflows/
  build-mcp-wrappers.yaml     # builds & pushes wrapper images to ghcr.io
```

## Bootstrap

```sh
kubectl apply -f argocd/platform-app.yaml   # root; cascades to per-ns apps + workloads
kubectl apply -f argocd/root-app.yaml       # deploy the MCP servers (app-of-apps)
```

The `platform` root syncs `argocd/platform-apps/`, which creates the AppProjects
(`sync-wave -1`, so they apply first) and the ten `platform-<namespace>`
app-of-apps. Each of those adopts the workload Applications in its
`argocd/<namespace>/` directory by name.

## Platform apps

The platform Application and AppProject definitions were exported from the live
cluster (2026-07-04), cleaned of runtime metadata, and organized by namespace:
each `argocd/<namespace>/` directory holds the workload Application(s) that
deploy into that namespace (e.g. `argocd/yugabytedb/` holds both `yugabyte` and
`pgadmin`). The grouping app for a namespace is named `platform-<namespace>` to
avoid colliding with a workload Application of the same name — every Argo CD
Application lives in the `argocd` namespace regardless of where it deploys, so
names must be unique cluster-wide. To change a workload's parameters, edit its
manifest in `argocd/<namespace>/` and push; the parent (`selfHeal: true`) applies
it. `prune` is disabled so deleting a manifest never cascade-deletes a live app.

Notes:
- The AppProject `sourceRepos` whitelists were extended to include the chart
  repos their apps actually use — `rancher` and `comfyui-gui` were stuck in
  sync status `Unknown` because their source repos were not whitelisted.
- `litellm` is git-managed (`argocd/litellm/`, wrapper `platform-litellm`). Its
  secrets are **not** inlined — they are standalone Secrets in the `litellm`
  namespace (`litellm-masterkey`, `litellm-postgresql-ext`, `litellm-dbcredentials`)
  referenced via `masterkeySecretName` and `postgresql.auth.existingSecret`,
  created out of band like the `mcp-*` servers.
- `vllm` (`argocd/vllm/`, wrapper `platform-vllm`) deploys the local
  `charts/vllm` wrapper chart: `vllm/vllm-openai` serving Qwen3-8B on the
  RTX 5090 (one time-slicing replica, `gpu-memory-utilization 0.60` since the
  GPU is shared with comfyui), with a Longhorn PVC caching the model download.
  `litellm` exposes it as model `qwen3-8b` via
  `http://vllm.vllm.svc.cluster.local:8000/v1`. No secret needed (Qwen is
  ungated); for gated models create a Secret with `HUGGING_FACE_HUB_TOKEN` and
  set `existingSecret`.
- `postgrest` still lives in `argocd/pending/` and is **not** synced from git:
  the colearendt/postgrest chart renders its Secret from literal Helm values
  (`postgrest.dbUri`, `postgrest.jwtSecret`) with no `existingSecret` support, so
  it needs a render-time secret plugin (SOPS/argocd-vault-plugin) before it can
  be committed. It remains managed directly in Argo CD, unchanged.

The root app syncs the per-server Applications; each deploys into the `mcp`
namespace. Servers that need credentials expect a pre-created Secret named
`<server>-mcp-env` (see table below) — create those with kubectl,
sealed-secrets, or external-secrets before or after the first sync (pods stay
in `CreateContainerConfigError` until the Secret exists). The exact
`kubectl create secret` command is in the header of each
`charts/mcp-server/values/<name>.yaml`.

## Servers

All image references were verified to exist in their registries (2026-07).
`morningstar` was removed: it required an existing paid Morningstar account/license.
`postman` was removed: the stdio-only pod was unreachable; LiteLLM uses Postman's hosted MCP server instead.
`obsidian` was removed: it talks to the Obsidian Local REST API community plugin, which
needs a running Obsidian app on the network to connect to - this homelab only has the vault
as a plain git repo (`homelab-vault`), with no Obsidian app instance anywhere to be a server.
The stdio-only `github` pod was also removed: GitHub is already registered via the official
hosted MCP server (see `litellm.yaml`), so a second, unreachable stdio GitHub pod was dead
weight.

### HTTP-native (Service enabled; Ingress available, disabled by default)

| Server | Image | Port | Secret (`<name>-mcp-env`) |
|---|---|---|---|
| grafana | `mcp/grafana` | 8000 | `GRAFANA_URL`, `GRAFANA_SERVICE_ACCOUNT_TOKEN` |
| playwright | `mcr.microsoft.com/playwright/mcp` | 8080 | — |
| huggingface | `ghcr.io/evalstate/hf-mcp-server` | 3000 | `HF_TOKEN` |
| kubernetes | official Helm chart `oci://ghcr.io/containers/charts/kubernetes-mcp-server` 0.1.3 (read/write, `edit` ClusterRole) | 8080 | — |
| linkedin | `stickerdaniel/linkedin-mcp-server:1.4.0` | 8000 | `LINKEDIN_COOKIE` |
| prometheus | `ghcr.io/pab1it0/prometheus-mcp-server` | 8080 | — (URL set via plain env) |
| paypal | `ghcr.io/lfoss0612/mcp-paypal` (wrapper) | 8080 | `PAYPAL_ACCESS_TOKEN`, `PAYPAL_ENVIRONMENT` |
| clickup | `ghcr.io/lfoss0612/mcp-clickup` (wrapper) | 8080 | `CLICKUP_PERSONAL_TOKEN` |
| argocd | `ghcr.io/lfoss0612/mcp-argocd` (wrapper) | 8080 | `ARGOCD_BASE_URL`, `ARGOCD_API_TOKEN` |
| finnhub | `ghcr.io/lfoss0612/mcp-finnhub` (wrapper) | 8080 | `FINNHUB_API_KEY` |
| memory | `ghcr.io/lfoss0612/mcp-memory` (wrapper) | 8080 | — |
| sequentialthinking | `ghcr.io/lfoss0612/mcp-sequentialthinking` (wrapper) | 8080 | — |
| git | `ghcr.io/lfoss0612/mcp-git` (wrapper) | 8080 | — |
| python-refactoring | `ghcr.io/lfoss0612/mcp-python-refactoring` (wrapper) | 8080 | — |
| code-interpreter | `ghcr.io/lfoss0612/mcp-code-interpreter` (wrapper) | 8080 | — |
| google-maps | `ghcr.io/lfoss0612/mcp-google-maps` (wrapper) | 8080 | `GOOGLE_MAPS_API_KEY` |
| proxmox | `ghcr.io/lfoss0612/mcp-proxmox` (wrapper) | 8080 | `PROXMOX_HOST`, `PROXMOX_USER`, `PROXMOX_TOKEN_NAME`, `PROXMOX_TOKEN_VALUE` |
| dockerhub | `ghcr.io/lfoss0612/mcp-dockerhub` (wrapper) | 8080 | `HUB_USERNAME`, `HUB_PAT_TOKEN` |

There are no stdio-only servers left in this repo — every server either has its own HTTP
transport, is a hosted MCP server, or got wrapped (see below). A stdio-only server has no
network endpoint, so MCP clients can't reach it over the cluster network; to add a new one,
either wrap it with [supergateway](https://github.com/supercorp-ai/supergateway) the way
`dockerfiles/` does, or confirm it's genuinely redundant/unreachable before adding it at all.

## Wrapper images (stdio bridged to HTTP)

Every server in the HTTP-native table above except the ones with their own
upstream image (grafana, playwright, huggingface, kubernetes, linkedin,
prometheus) has no streamable-HTTP transport of its own, so
`dockerfiles/<name>/Dockerfile` bridges its stdio transport to HTTP (port
8080, health endpoint `/healthz`) via supergateway:

- **npm-only** (paypal, clickup, argocd, finnhub): no upstream image at all;
  the Dockerfile installs the npm package directly.
- **wrapping an existing upstream image** (memory, sequentialthinking, git,
  python-refactoring, code-interpreter, google-maps, proxmox, dockerhub):
  `FROM mcp/<name>` (or equivalent). The upstream image's own `ENTRYPOINT`
  must be cleared (`ENTRYPOINT []`) before this wrapper's `CMD`, or the
  supergateway invocation becomes arguments to it instead of replacing it.
  Debian-based ones with no node at all get it via apt — NodeSource for a
  current LTS where Debian's own package is too old for the MCP SDK's
  global WebCrypto API (hit this on bookworm's node 18). A couple of
  upstream images (git, code-interpreter) also ship file permissions that
  don't survive this chart's forced non-root `runAsUser: 10001` — fixed
  with a `chown` in the wrapper layer, not by weakening the chart's
  security context.

The GitHub Actions workflow builds and pushes all of them to
`ghcr.io/lfoss0612/mcp-<name>` on every push to `main` that touches
`dockerfiles/` — make the ghcr packages public (or add an imagePullSecret)
after the first push.

Local build, if preferred:

```sh
docker build -f dockerfiles/paypal/Dockerfile -t ghcr.io/lfoss0612/mcp-paypal:latest .
docker push ghcr.io/lfoss0612/mcp-paypal:latest
```

## Ingress and TLS

Ingress is templated but disabled everywhere by default. Enable per server in
`charts/mcp-server/values/<name>.yaml`:

```yaml
ingress:
  enabled: true
  className: nginx
  host: grafana.mcp.homelab.local
  tls:
    enabled: true          # expects cert-manager or a pre-created TLS secret
    secretName: ""         # defaults to <release>-tls
```

## Chart defaults worth knowing

- Hardened pod security context (non-root uid 10001, seccomp, no capabilities);
  `playwright` overrides it because the browser needs its own sandboxing.
- Default resources: 50m/128Mi requests, 512Mi memory limit.
- `secret.create` can render a Secret from inline values — prefer
  `envFromSecrets` with an external secret manager; never commit credentials.
- Wrapper images have HTTP probes enabled against `/healthz`.
