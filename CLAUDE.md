# Claude Code working context

GitOps repo for the homelab Kubernetes cluster, managed by **Argo CD** with a
nested app-of-apps pattern. Two independent trees + a small unsynced set:

- **platform** — pre-existing cluster apps (cert-manager, longhorn, rancher,
  gpu-operator, yugabyte, litellm, vllm, ...), organized **by namespace**.
  `argocd/platform-app.yaml` → `argocd/platform-apps/<ns>.yaml` (one
  `platform-<ns>` app-of-apps each) → workloads in `argocd/<ns>/`.
- **mcp-servers** — one Argo CD Application per MCP server, all instantiating the
  single reusable `charts/mcp-server` Helm chart. `argocd/root-app.yaml` →
  `argocd/apps/mcp-<name>.yaml`.
- **pending** — `argocd/pending/` (litellm*, postgrest): **not synced from git**
  because their specs embed credentials; managed directly in Argo CD.

Full detail lives in **[README.md](README.md)** (server table, secrets, wrapper
images) and **[docs/architecture.md](docs/architecture.md)** (app-of-apps
diagrams, change-flow). Read those before deep work; don't duplicate them here.

## Routing — use these first

- Broken app / sync / TLS / duplicate-resource issue → **`k8s-diagnostics`**
  agent to find root cause (read-only) *before touching anything*.
- Fix committed & pushed, need Argo CD to pick it up now → **`argocd-force-sync`**
  skill.
- Grafana dashboard YAML/API work (`argocd/cattle-monitoring-system/*.yaml`) →
  **`grafana-dashboard-ops`** skill.
- Onboarding a brand-new app into the app-of-apps structure →
  **`add-gitops-app`** skill.
- Documenting an incident after the fix → **`incident-note`** skill (writes to
  the `homelab-vault` Obsidian repo, not here).

## Conventions & gotchas (know these before editing)

- **Strict GitOps.** Every app is `selfHeal: true` — edit manifests in git and
  push, never patch live objects in the Argo CD UI (overrides get reverted).
  `prune: false` on the platform tree, so deleting a manifest does **not**
  cascade-delete a live app.
- **Every Argo CD `Application` lives in the `argocd` namespace**, regardless of
  where it deploys (`spec.destination.namespace`). App names must be unique
  cluster-wide — that's why per-namespace wrappers are `platform-<ns>`, distinct
  from the workload of the same name. A git dir like `argocd/cert-manager/` is
  just a folder, not a namespace.
- **Never commit credentials.** Secrets are created out-of-band (kubectl /
  sealed-secrets / external-secrets). MCP servers expect a pre-created Secret
  `<server>-mcp-env`; the exact `kubectl create secret` command is in the header
  of each `charts/mcp-server/values/<name>.yaml`. Pods stay in
  `CreateContainerConfigError` until the Secret exists.
- **Adding an MCP server** = new `charts/mcp-server/values/<name>.yaml` +
  `argocd/apps/mcp-<name>.yaml`; the `add-gitops-app` skill handles the wiring.
- **stdio-only servers get bridged to HTTP via supergateway**, not left stdio-only, unless
  they're redundant with an existing hosted entry (github's stdio pod vs. the hosted GitHub
  MCP server) or there's no real backend to connect to (obsidian was removed: it needs a
  running Obsidian app with the Local REST API plugin, and this homelab only has the vault
  as a plain git repo). `dockerfiles/<name>/` wraps them: npm-only servers (paypal, clickup,
  argocd, finnhub) install the npm package directly; others (memory, sequentialthinking, git,
  python-refactoring, code-interpreter, google-maps, proxmox, dockerhub) wrap an existing
  `mcp/<name>` upstream image, clearing its own `ENTRYPOINT` first (or this wrapper's CMD
  becomes arguments to it instead of replacing it) and adding node+npm on top for
  Debian-based ones with none — apt, or NodeSource for a current LTS where Debian's own
  package is too old for the MCP SDK's global WebCrypto API (hit this on bookworm's node 18).
  Built to `ghcr.io/lfoss0612/mcp-<name>` by `.github/workflows/build-mcp-wrappers.yaml` on
  push to `main`.
- **This chart forces `runAsUser: 10001`** on every pod regardless of the image's own user.
  A wrapped upstream image whose files aren't world-readable/executable at that uid fails
  with "permission denied" (hit this with git and code-interpreter) — fix with `chown` in
  the wrapper Dockerfile, never by weakening `podSecurityContext` in the shared chart.

## Git in this repo (NFS workaround)

`/mnt/projects` is NFS, which breaks git object writes, so `.git/objects` is a
**symlink** to `/home/lfoss/.local/share/git-objects/homelab-gitops` (local
disk) — leave it alone. The stored `gh`/PAT token lacks `workflow` scope, so
pushes that touch `.github/workflows/` will be rejected.
