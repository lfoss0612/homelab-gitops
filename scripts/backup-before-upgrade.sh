#!/usr/bin/env bash
# One entry point for the backups to take before upgrading something on the cluster.
#
# Dry run by default: it prints what it would do and changes nothing. Add --apply to act.
#
# What it can do (pick the parts you need):
#   Longhorn volumes   a snapshot and a backup per attached volume, with a unique snapshot name
#                      per volume (pre-<label>-<8 hex>), then waits until every backup is
#                      Completed. Select volumes with --namespaces a,b or --all. Volumes whose
#                      actual size is over --max-actual-gb (default 100) are skipped so a huge
#                      volume such as the Ollama models is never backed up by accident; detached
#                      volumes cannot be snapshotted and are listed as skipped.
#   etcd               check that a recent snapshot exists, and with --etcd-save take a new
#                      pre-<label> one on the control plane (see ETCD_SAVE_CMD below).
#   Argo CD export     --argocd-export writes Applications, ApplicationSets, AppProjects and the
#                      argocd Secrets to a file readable only by you, outside git.
#   Yugabyte dump      --ysql-dump DB (repeatable) writes a logical dump of one database.
#
# Usage:
#   scripts/backup-before-upgrade.sh --label cert-manager-1-21 --namespaces yugabytedb --etcd-save
#   scripts/backup-before-upgrade.sh --label argocd-10 --argocd-export --etcd-save --apply
#
# Options:
#   --label NAME          required; becomes part of every snapshot name (lowercase, digits, -)
#   --namespaces A,B      back up the Longhorn volumes of these namespaces
#   --all                 back up every attached volume (still subject to --max-actual-gb)
#   --skip-pvc P1,P2      PVC names to leave out
#   --max-actual-gb N     skip volumes using more than N GiB (default 100)
#   --etcd-save           take an etcd snapshot named pre-<label> (with --apply)
#   --etcd-max-age-min N  fail the etcd check if the newest snapshot is older (default 90)
#   --argocd-export       export the argocd namespace objects (with --apply)
#   --ysql-dump DB        dump this YSQL database (repeatable, with --apply)
#   --timeout-min N       wait this long for backups to complete (default 45)
#   --dir PATH            where exports and dumps go (default ~/.local/share/homelab-upgrade-backups)
#   --apply               really do it
#   -h, --help
#
# Environment:
#   ETCD_SAVE_CMD  command that takes the etcd snapshot; the token LABEL is replaced by pre-<label>.
#                  Default goes through the homelab-ansible wrapper in the sibling checkout:
#                  ../homelab-ansible/scripts/ansible-on-cockpit.sh adhoc k8s-master.home.lan ...
#   KUBECONFIG     as usual.
#
# Exit status is 0 only if everything requested succeeded. Nothing here deletes anything.

set -euo pipefail

label=""; namespaces=""; all=0; skip_pvc=""; max_gb=100
etcd_save=0; etcd_max_age=90; argocd_export=0; timeout_min=45; apply=0
dbs=()
out_root="${HOME}/.local/share/homelab-upgrade-backups"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ansible_repo="${ANSIBLE_REPO:-$here/../../homelab-ansible}"

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "error: $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --label) label="${2:?}"; shift 2 ;;
    --namespaces) namespaces="${2:?}"; shift 2 ;;
    --all) all=1; shift ;;
    --skip-pvc) skip_pvc="${2:?}"; shift 2 ;;
    --max-actual-gb) max_gb="${2:?}"; shift 2 ;;
    --etcd-save) etcd_save=1; shift ;;
    --etcd-max-age-min) etcd_max_age="${2:?}"; shift 2 ;;
    --argocd-export) argocd_export=1; shift ;;
    --ysql-dump) dbs+=("${2:?}"); shift 2 ;;
    --timeout-min) timeout_min="${2:?}"; shift 2 ;;
    --dir) out_root="${2:?}"; shift 2 ;;
    --apply) apply=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ "$label" =~ ^[a-z0-9][a-z0-9-]{0,30}$ ]] || die "--label is required: lowercase letters, digits and dashes, up to 31 characters"
command -v kubectl >/dev/null || die "kubectl not found"
command -v python3 >/dev/null || die "python3 not found"

stamp="$(date +%Y%m%d-%H%M%S)"
work="$out_root/$label-$stamp"
status=0
summary=()

mode="DRY RUN"; [ "$apply" -eq 1 ] && mode="APPLY"
echo "== backup-before-upgrade: $label ($mode)"

# ---------------------------------------------------------------- Longhorn
plan="$(python3 - "$namespaces" "$all" "$skip_pvc" "$max_gb" <<'PY'
import json, subprocess, sys
namespaces = {n for n in sys.argv[1].split(",") if n}
select_all = sys.argv[2] == "1"
skip = {n for n in sys.argv[3].split(",") if n}
max_gb = float(sys.argv[4])
raw = subprocess.run(["kubectl", "get", "volumes.longhorn.io", "-n", "longhorn-system", "-o", "json"],
                     capture_output=True, text=True, check=True).stdout
rows = []
for v in json.loads(raw)["items"]:
    ks = v["status"].get("kubernetesStatus", {})
    ns, pvc = ks.get("namespace") or "-", ks.get("pvcName") or v["metadata"]["name"]
    if not select_all and ns not in namespaces:
        continue
    actual = int(v["status"].get("actualSize", 0)) / 2**30
    state = v["status"].get("state")
    robust = v["status"].get("robustness")
    why = ""
    if pvc in skip:
        why = "skipped (--skip-pvc)"
    elif state != "attached":
        why = f"skipped (volume is {state}, cannot be snapshotted)"
    elif actual > max_gb:
        why = f"skipped ({actual:.0f} GiB over --max-actual-gb {max_gb:.0f})"
    elif robust == "faulted":
        why = "skipped (faulted)"
    rows.append([v["metadata"]["name"], ns, pvc, f"{actual:.1f}", robust or "-", why])
for r in sorted(rows, key=lambda r: (r[1], r[2])):
    print("\t".join(r))
PY
)"

if [ -z "$namespaces" ] && [ "$all" -eq 0 ]; then
  echo "-- Longhorn: not requested (use --namespaces or --all)"
else
  echo "-- Longhorn volumes"
  if [ -z "$plan" ]; then echo "   no matching volumes"; fi
  todo=()
  while IFS=$'\t' read -r vol ns pvc size robust why; do
    [ -n "$vol" ] || continue
    if [ -n "$why" ]; then
      printf '   %-24s %-36s %6s GiB  %s\n' "$ns" "$pvc" "$size" "$why"
    else
      printf '   %-24s %-36s %6s GiB  %s -> will back up\n' "$ns" "$pvc" "$size" "$robust"
      todo+=("$vol|$ns|$pvc")
    fi
  done <<<"$plan"
  summary+=("Longhorn: ${#todo[@]} volume(s) selected")

  if [ "$apply" -eq 1 ] && [ "${#todo[@]}" -gt 0 ]; then
    declare -A snapname
    echo "-- creating snapshots"
    for item in "${todo[@]}"; do
      IFS='|' read -r vol ns pvc <<<"$item"
      name="pre-$label-$(openssl rand -hex 4)"
      snapname[$vol]="$name"
      kubectl create -f - >/dev/null 2> >(grep -v 'prefer a domain-qualified' >&2) <<EOF
apiVersion: longhorn.io/v1beta2
kind: Snapshot
metadata:
  name: $name
  namespace: longhorn-system
spec:
  volume: $vol
  createSnapshot: true
EOF
    done
    for item in "${todo[@]}"; do
      IFS='|' read -r vol ns pvc <<<"$item"
      name="${snapname[$vol]}"
      for _ in $(seq 1 60); do
        ready="$(kubectl get snapshots.longhorn.io "$name" -n longhorn-system -o jsonpath='{.status.readyToUse}' 2>/dev/null || true)"
        [ "$ready" = "true" ] && break
        sleep 5
      done
      if [ "${ready:-}" != "true" ]; then echo "   snapshot $name of $pvc not ready"; status=1; unset 'snapname[$vol]'; fi
    done
    echo "-- creating backups"
    for item in "${todo[@]}"; do
      IFS='|' read -r vol ns pvc <<<"$item"
      [ -n "${snapname[$vol]:-}" ] || continue
      name="${snapname[$vol]}"
      kubectl create -f - >/dev/null 2> >(grep -v 'prefer a domain-qualified' >&2) <<EOF
apiVersion: longhorn.io/v1beta2
kind: Backup
metadata:
  name: $name
  namespace: longhorn-system
  labels:
    backup-volume: $vol
spec:
  snapshotName: $name
  backupMode: incremental
  labels:
    longhorn.io/volume-access-mode: rwo
    pre-upgrade: $label
EOF
    done
    echo "-- waiting for backups (up to $timeout_min min)"
    deadline=$(( $(date +%s) + timeout_min * 60 ))
    for item in "${todo[@]}"; do
      IFS='|' read -r vol ns pvc <<<"$item"
      [ -n "${snapname[$vol]:-}" ] || continue
      name="${snapname[$vol]}"
      state=""
      while [ "$(date +%s)" -lt "$deadline" ]; do
        state="$(kubectl get backups.longhorn.io "$name" -n longhorn-system -o jsonpath='{.status.state}' 2>/dev/null || true)"
        case "$state" in Completed|Error|Unknown) break ;; esac
        sleep 10
      done
      printf '   %-36s %s (%s)\n' "$pvc" "${state:-no state}" "$name"
      [ "$state" = "Completed" ] || status=1
    done
    summary+=("Longhorn backups: $([ $status -eq 0 ] && echo all Completed || echo SOME FAILED, see above)")
  fi
fi

# -------------------------------------------------------------------- etcd
echo "-- etcd"
newest="$(kubectl get etcdsnapshotfiles.k3s.cattle.io -o json 2>/dev/null | python3 -c "
import json, sys, datetime
items = json.load(sys.stdin)['items']
best = None
for i in items:
    t = i['status'].get('creationTime') or i['metadata']['creationTimestamp']
    d = datetime.datetime.fromisoformat(t.replace('Z', '+00:00'))
    if best is None or d > best[0]: best = (d, i['spec'].get('snapshotName', ''))
if best:
    age = (datetime.datetime.now(datetime.timezone.utc) - best[0]).total_seconds() / 60
    print(f'{age:.0f} {best[1]}')
" 2>/dev/null || true)"
if [ -n "$newest" ]; then
  echo "   newest snapshot: ${newest#* } (${newest%% *} min old)"
  if [ "${newest%% *}" -gt "$etcd_max_age" ] && [ "$etcd_save" -eq 0 ]; then
    echo "   WARNING: older than $etcd_max_age min; add --etcd-save"
    summary+=("etcd: newest snapshot is stale")
  else
    summary+=("etcd: recent snapshot exists")
  fi
else
  echo "   could not read etcd snapshots"
fi
if [ "$etcd_save" -eq 1 ]; then
  cmd="${ETCD_SAVE_CMD:-$ansible_repo/scripts/ansible-on-cockpit.sh adhoc k8s-master.home.lan -m command -a \"/usr/local/bin/rke2 etcd-snapshot save --name LABEL\"}"
  cmd="${cmd//LABEL/pre-$label}"
  if [ "$apply" -eq 1 ]; then
    echo "   taking pre-$label"
    if eval "$cmd" >/tmp/etcd-save.$$ 2>&1; then
      for _ in $(seq 1 12); do
        kubectl get etcdsnapshotfiles.k3s.cattle.io -o jsonpath='{.items[*].spec.snapshotName}' | tr ' ' '\n' | grep -q "^pre-$label" && { found=1; break; }
        sleep 5
      done
      if [ "${found:-0}" = 1 ]; then echo "   snapshot pre-$label recorded"; summary+=("etcd: pre-$label taken"); else echo "   command ran but no pre-$label snapshot appeared"; status=1; fi
    else
      echo "   etcd snapshot command failed:"; sed 's/^/     /' /tmp/etcd-save.$$ | tail -5; status=1
    fi
    rm -f /tmp/etcd-save.$$
  else
    echo "   would run: $cmd"
  fi
fi

# --------------------------------------------------------------- Argo CD
if [ "$argocd_export" -eq 1 ]; then
  echo "-- Argo CD export"
  if [ "$apply" -eq 1 ]; then
    mkdir -p "$work"; chmod 700 "$out_root" "$work"
    f="$work/argocd-export.yaml"
    umask 077
    kubectl get applications.argoproj.io,applicationsets.argoproj.io,appprojects.argoproj.io,secrets,configmaps \
      -n argocd -o yaml >"$f"
    echo "   wrote $f ($(wc -c <"$f") bytes, mode $(stat -c %a "$f"); contains secrets, keep out of git)"
    summary+=("Argo CD export: $f")
  else
    echo "   would write the argocd Applications, ApplicationSets, AppProjects, Secrets and ConfigMaps under $out_root"
  fi
fi

# --------------------------------------------------------------- Yugabyte
for db in "${dbs[@]:-}"; do
  [ -n "$db" ] || continue
  echo "-- YSQL dump of $db"
  if [ "$apply" -eq 1 ]; then
    mkdir -p "$work"; chmod 700 "$out_root" "$work"
    f="$work/ysql-$db.sql"
    umask 077
    if kubectl exec -n yugabytedb yb-tserver-0 -c yb-tserver -- \
         bash -c "/home/yugabyte/postgres/bin/ysql_dump -h \$(hostname) -d '$db'" >"$f"; then
      echo "   wrote $f ($(wc -c <"$f") bytes)"; summary+=("YSQL dump: $f")
    else
      echo "   dump failed"; status=1
    fi
  else
    echo "   would dump database $db from yb-tserver-0 into $out_root"
  fi
done

echo
echo "== summary ($mode)"
for s in "${summary[@]:-}"; do [ -n "$s" ] && echo "   $s"; done
if [ "$apply" -eq 0 ]; then echo "   nothing was changed; add --apply to act"; fi
exit "$status"
