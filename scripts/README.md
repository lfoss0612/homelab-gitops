# scripts

Helpers for upgrading things on the cluster. Each one is a dry run unless you pass `--apply`.

## backup-before-upgrade.sh

One entry point for the backups to take before an upgrade: Longhorn snapshots and backups (a unique
snapshot name per volume, waits until each backup is Completed), an etcd snapshot, an Argo CD
namespace export (mode 600, outside git) and an optional YSQL dump.

```bash
# See what it would do for the Yugabyte and Open WebUI volumes, plus etcd and an Argo CD export
scripts/backup-before-upgrade.sh --label yb-2025-3 --namespaces yugabytedb,open-webui --etcd-save --argocd-export

# Do it
scripts/backup-before-upgrade.sh --label yb-2025-3 --namespaces yugabytedb --etcd-save --apply
```

- Volumes using more than `--max-actual-gb` (default 100) are skipped, so the 431 GiB Ollama model
  volume is never backed up by accident. Detached volumes cannot be snapshotted and are listed as
  skipped; take a backup after attaching them if they matter.
- The etcd snapshot is taken through the homelab-ansible wrapper in the sibling checkout
  (`../homelab-ansible`); override with `ETCD_SAVE_CMD` (the token `LABEL` becomes `pre-<label>`).
- The export and dumps go to `~/.local/share/homelab-upgrade-backups/<label>-<time>/` (directory
  mode 700). They contain secrets: never commit them.
- Nothing here deletes anything. Old `pre-*` snapshots and backups are removed by hand.

## chart-outdated.py

Read-only. Lists every Argo CD Helm app whose chart is behind the latest in its repository, in the
order to upgrade (tier 1 routine first, Argo CD last), with the size of the jump and the chart's home
page. Tiers and per-app care come from [docs/app-upgrade-risks.md](../docs/app-upgrade-risks.md).
Needs `kubectl` and `helm`; uses a throw-away helm config, so your `helm repo` list is untouched.

```bash
scripts/chart-outdated.py          # only what is behind
scripts/chart-outdated.py --all    # everything
scripts/chart-outdated.py --json
```

## chart-diff.py

Read-only. Renders an Argo CD Helm app at two chart versions with the values the Application really
uses and flags the dangerous changes: immutable selector changes, CRDs (size), new NetworkPolicies,
removed RBAC objects, Helm hooks, values the Application sets that the new chart no longer declares,
and every image change. Writes the full rendered diff to a mode-700 temp directory.

```bash
scripts/chart-diff.py yugabyte --new 2026.1.3        # old = what the Application pins today
scripts/chart-diff.py argocd 10.18.0 10.18.2
```

The `chart-upgrade` skill (`.claude/skills/chart-upgrade/`) is the checklist that uses it.
