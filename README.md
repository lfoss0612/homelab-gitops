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
  paypal/  monday/  argocd/   # pinned wrapper Dockerfiles for npm-only servers
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
`morningstar` was removed: no container image or npm package exists.

### HTTP-native (Service enabled; Ingress available, disabled by default)

| Server | Image | Port | Secret (`<name>-mcp-env`) |
|---|---|---|---|
| grafana | `mcp/grafana` | 8000 | `GRAFANA_URL`, `GRAFANA_SERVICE_ACCOUNT_TOKEN` |
| playwright | `mcr.microsoft.com/playwright/mcp` | 8080 | — |
| huggingface | `ghcr.io/evalstate/hf-mcp-server` | 3000 | `HF_TOKEN` |
| linkedin | `stickerdaniel/linkedin-mcp-server:1.4.0` | 8000 | `LINKEDIN_COOKIE` |
| prometheus | `ghcr.io/pab1it0/prometheus-mcp-server` | 8080 | — (URL set via plain env) |
| paypal | `ghcr.io/lfoss0612/mcp-paypal` (wrapper) | 8080 | `PAYPAL_ACCESS_TOKEN`, `PAYPAL_ENVIRONMENT` |
| monday | `ghcr.io/lfoss0612/mcp-monday` (wrapper) | 8080 | `MONDAY_TOKEN` |
| argocd | `ghcr.io/lfoss0612/mcp-argocd` (wrapper) | 8080 | `ARGOCD_BASE_URL`, `ARGOCD_API_TOKEN` |

### stdio-only (no Service; kept alive with stdin/tty)

| Server | Image | Secret (`<name>-mcp-env`) |
|---|---|---|
| github | `ghcr.io/github/github-mcp-server` | `GITHUB_PERSONAL_ACCESS_TOKEN` |
| memory | `mcp/memory` | — |
| sequentialthinking | `mcp/sequentialthinking` | — |
| git | `mcp/git` | — |
| obsidian | `mcp/obsidian` | `OBSIDIAN_API_KEY`, `OBSIDIAN_HOST` |
| kubernetes | `mcp/kubernetes` | — (uses service account; grant RBAC separately) |
| postman | `mcp/postman` | `POSTMAN_API_KEY` |
| python-refactoring | `mcp/mcp-python-refactoring` | — |
| code-interpreter | `mcp/mcp-code-interpreter` | — |
| google-maps | `mcp/google-maps` | `GOOGLE_MAPS_API_KEY` |
| proxmox | `mcp/proxmox` | `PROXMOX_HOST`, `PROXMOX_USER`, `PROXMOX_TOKEN_NAME`, `PROXMOX_TOKEN_VALUE` |
| dockerhub | `mcp/dockerhub` | `HUB_USERNAME`, `HUB_PAT_TOKEN` |

stdio-only servers have no network endpoint — MCP clients cannot reach them
over the cluster network. To expose one over HTTP, wrap it with
[supergateway](https://github.com/supercorp-ai/supergateway) the way the npm
wrappers in `dockerfiles/` do.

## Wrapper images (npm-only servers)

PayPal, monday.com, and Argo CD ship as npm packages, not container images.
`dockerfiles/<name>/Dockerfile` pins each package and bridges its stdio
transport to streamable HTTP (port 8080, health endpoint `/healthz`) via
supergateway. The GitHub Actions workflow builds and pushes them to
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
