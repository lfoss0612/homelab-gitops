# Upgrade risk notes per app

The apps that need care when their chart is bumped. `scripts/chart-outdated.py` reads this table
(the app name is the Argo CD Application name), orders its output by tier, and prints the note;
the `chart-upgrade` skill points here so the checklist does not rely on memory.

Tiers say the order to upgrade in and how much ceremony to use:

1. routine: bump, render diff, sync, check pods
2. care: a diff that touches selectors, CRDs, NetworkPolicies or RBAC is likely; read the notes
3. data or platform: a backup first (`scripts/backup-before-upgrade.sh`), one at a time, verify
   data afterwards
4. last: upgrade everything else first, export first, and expect the UI to blip

`-` means the app's version is set by another component and is not reported as "behind" (rancher-webhook follows Rancher); it moves in the same change as that component.

| App | Tier | Care |
|---|---|---|
| `pgadmin` | 1 | `*` target revision: the live version is the one Argo resolved; pin it when bumping |
| `zabbix-proxy-agent` | 1 | Check the agent still reports to the proxy afterwards |
| `metal` | 2 | `*` target revision, as above. Check the IPAddressPool and L2Advertisement survive |
| `cert-manager` | 2 | CRDs: confirm they are established before the sync finishes; check Certificates renew |
| `langflow-ide` | 2 | Check the Postgres connection and the persistent volume after the sync |
| `litellm` | 2 | OCI chart (ghcr.io), pinned in `argocd/litellm/litellm.yaml`; the chart runs a DB migration job (one-way), and the model catalogue lives in its Postgres, so a Longhorn backup of `data-litellm-postgresql-0` comes first |
| `open-webui` | 2 | Ollama model volume is huge: never part of a backup; check the GPU is still seen |
| `rancher-monitoring` | 2 | Bump together with `rancher-monitoring-crd`; large CRDs need `ServerSideApply` |
| `rancher-monitoring-crd` | 2 | Bump together with `rancher-monitoring` |
| `rancher-webhook` | - | follows Rancher: its version is set by the Rancher release, so bump `targetRevision` in `argocd/cattle-system/rancher-webhook.yaml` together with the Rancher upgrade, never on its own |
| `system-upgrade-controller` | 2 | Rancher 2.15 took over this chart; the plan must not drain (Longhorn PDB hangs) |
| `gpu-operator` | 3 | After a driver or kernel change run `nvidia-smi` and check the operator pods and Ollama |
| `rancher` | 3 | Read the notes for removed ServiceAccounts and bundled charts it takes over; watch the per-node pod limit for a burst of helm-operation pods |
| `longhorn` | 3 | Backups first. The engine upgrade comes after the chart: `scripts/longhorn-engine-upgrade.sh` |
| `yugabyte` | 3 | Logical dump first (`--ysql-dump`); StatefulSet selectors are immutable (`--cascade=orphan` delete) |
| `mongodb` | 3 | Paused (replicas 0) while MongoDB 8 cannot run on kernel 6.19 or newer; do not unpause by accident |
| `argocd` | 4 | Export first (`--argocd-export`) and upgrade last; the UI drops while it restarts; keep NetworkPolicies off |

Apps whose chart lives in this repository (`comfyui-gui`, `postgrest`, `vllm`, `mongodb`) are not
compared against a repository; change them like any other manifest.
