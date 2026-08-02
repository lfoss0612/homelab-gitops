# OpenClaw working convention

OpenClaw follows the same conventions as any other agent working in this repo —
see **[CLAUDE.md](CLAUDE.md)** for the full working context (the app-of-apps
layout, routing to the right skill/agent, and the GitOps gotchas), with deeper
detail in [README.md](README.md) and [docs/architecture.md](docs/architecture.md).

In short: this is a **strict GitOps** repo managed by Argo CD — edit manifests in
git and push, never patch live objects (every app is `selfHeal: true`, so
UI/kubectl overrides get reverted). **Never commit credentials**; secrets are
created out-of-band. For a broken app or sync/TLS/duplicate-resource issue, start
with the `k8s-diagnostics` agent (read-only) before touching anything.

## Read plane vs write plane

Standing fleet decision (2026-08-01), which this repo is one third of:

- **OpenClaw nodes = read plane.** Observe, tail logs, inspect state, debug. No
  mutation of the host they run on.
- **Ansible (`homelab-ansible`, from cockpit) = write plane for hosts.**
- **Argo CD (this repo) = write plane for everything in-cluster.**

`k8s-master`, `k8s-worker`, and `k8s-worker-2` are all OpenClaw nodes, so this
matters here specifically: a local fix applied on one of those hosts fights
`selfHeal` and gets reverted. Cluster changes go through a commit here; host-level
changes to those same machines go through an Ansible playbook. Neither is ever a
hand edit on the box.

Reasoning and current enforcement gaps: `homelab-ansible/docs/execution-model.md`.
