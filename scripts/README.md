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
