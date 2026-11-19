#!/usr/bin/env bash
# Move Longhorn volumes to a new engine image with the live engine upgrade (no detach), one volume
# at a time, refusing to continue unless each step is healthy. Run it AFTER the Longhorn chart bump,
# when the new engine image shows as deployed (kubectl get engineimages.longhorn.io -n longhorn-system).
#
# Dry run by default: prints the plan and the gates it would check, changes nothing. --apply acts.
#
# Per attached volume, before: attached, robustness healthy, no rebuild, every replica on the old image,
# every engine replica in RW mode, and the gate command of its namespace (if any) succeeds.
# Then the engineUpgrade action. Then it waits until the engine and every replica run the new image,
# the replicas are RW and the volume is healthy again, and runs the namespace gate again.
# Any failed check stops the whole run (exit 1) with the volume left as it is; set the old image back
# the same way (re-run with --image <old tag> --volume NAME) if you need to revert.
# Detached volumes just get the new image set; it takes effect on their next attach.
# Degraded attached volumes are skipped and listed (upgrading a degraded volume risks its only replica).
#
# Usage:
#   scripts/longhorn-engine-upgrade.sh                      # plan, newest deployed engine image
#   scripts/longhorn-engine-upgrade.sh --volume pvc-x --apply   # try ONE volume first
#   scripts/longhorn-engine-upgrade.sh --apply \
#       --gate 'yugabytedb=kubectl exec -n yugabytedb yb-tserver-0 -c yb-tserver -- yb-admin -master_addresses yb-masters:7100 list_all_tablet_servers | grep -q ALIVE'
#
# Options:
#   --image TAG|IMAGE   target engine image, e.g. v1.13.1 or docker.io/longhornio/longhorn-engine:v1.13.1
#                       (default: the newest engine image in state deployed)
#   --volume NAME       only this volume (repeatable); do the test volume first
#   --gate NS=CMD       a command that must succeed before and after each volume of namespace NS
#                       (repeatable); volumes in gated namespaces go last
#   --timeout S         seconds to wait for each volume to settle (default 180)
#   --apply             really do it
# Needs kubectl and jq. Talks to Longhorn through the API server's service proxy: no port-forward.
set -euo pipefail

ns=longhorn-system; apply=0; timeout=180; target=""; only=(); gates=()
die() { echo "error: $*" >&2; exit 2; }
usage() { sed -n '2,/^set -/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }
while [ $# -gt 0 ]; do
  case "$1" in
    --image) target="${2:?}"; shift 2 ;;
    --volume) only+=("${2:?}"); shift 2 ;;
    --gate) gates+=("${2:?}"); shift 2 ;;
    --timeout) timeout="${2:?}"; shift 2 ;;
    --apply) apply=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option $1" ;;
  esac
done
command -v jq >/dev/null || die "jq is required"
proxy="/api/v1/namespaces/$ns/services/longhorn-backend:9500/proxy/v1"

# ---- target image
images="$(kubectl get engineimages.longhorn.io -n "$ns" -o json)"
if [ -z "$target" ]; then
  target="$(jq -r '[.items[] | select(.status.state=="deployed")] | sort_by(.metadata.creationTimestamp) | last | .spec.image // empty' <<<"$images")"
  [ -n "$target" ] || die "no deployed engine image found"
fi
case "$target" in */*) ;; *) target="docker.io/longhornio/longhorn-engine:$target" ;; esac
state="$(jq -r --arg i "$target" '.items[] | select(.spec.image==$i) | .status.state' <<<"$images")"
[ "$state" = deployed ] || die "engine image $target is not deployed (state: ${state:-absent}). Bump the Longhorn chart first and wait for it."
echo "Target engine image: $target"

# ---- helpers
gate_for() { local n="$1" g; for g in "${gates[@]:-}"; do [ "${g%%=*}" = "$n" ] && { echo "${g#*=}"; return; }; done; }
vol_json() { kubectl get volumes.longhorn.io -n "$ns" "$1" -o json; }
engine_json() { kubectl get engines.longhorn.io -n "$ns" -l "longhornvolume=$1" -o json; }
replicas_json() { kubectl get replicas.longhorn.io -n "$ns" -l "longhornvolume=$1" -o json; }

# Echoes nothing when the volume is settled on $2, otherwise why it is not.
unsettled() {
  local v="$1" img="$2" e r vj
  vj="$(vol_json "$v")"
  [ "$(jq -r '.status.robustness' <<<"$vj")" = healthy ] || { echo "robustness is $(jq -r '.status.robustness' <<<"$vj")"; return; }
  e="$(engine_json "$v")"; r="$(replicas_json "$v")"
  jq -e --arg i "$img" '[.items[] | .status.currentImage == $i] | all' <<<"$e" >/dev/null || { echo "engine not on new image yet"; return; }
  jq -e --arg i "$img" '[.items[] | .status.currentImage == $i] | all' <<<"$r" >/dev/null || { echo "a replica is not on the new image yet"; return; }
  jq -e '[.items[].status.replicaModeMap // {} | to_entries[] | .value == "RW"] | all' <<<"$e" >/dev/null || { echo "an engine replica is not RW"; return; }
}
run_gate() { # $1 namespace, $2 label
  local g; g="$(gate_for "$1")"; [ -n "$g" ] || return 0
  if bash -c "$g" >/dev/null 2>&1; then echo "    gate ($1) $2: ok"; else echo "    gate ($1) $2: FAILED: $g" >&2; return 1; fi
}

# ---- plan
all="$(kubectl get volumes.longhorn.io -n "$ns" -o json)"
gated_ns="$(printf '%s\n' "${gates[@]:-}" | sed 's/=.*//' | grep . || true)"
plan="$(jq -r --arg img "$target" --arg only "$(IFS=,; echo "${only[*]:-}")" --arg gated "$(echo "$gated_ns" | paste -sd, -)" '
  ($only | split(",") | map(select(. != ""))) as $o
  | ($gated | split(",")) as $g
  | [.items[]
      | select(.spec.image != $img or .status.currentImage != $img)
      | select(($o | length) == 0 or (.metadata.name as $n | $o | index($n)))
      | {name: .metadata.name, ns: (.status.kubernetesStatus.namespace // "-"), state: .status.state, rob: .status.robustness,
         pvc: (.status.kubernetesStatus.pvcName // "-"), from: (.status.currentImage // .spec.image), gated: ((.status.kubernetesStatus.namespace // "-") as $x | $g | index($x) != null)}]
  | sort_by([.gated, .ns, .name]) | .[] | [.name, .ns, .pvc, .state, .rob, .from] | @tsv' <<<"$all")"
[ -n "$plan" ] || { echo "Every selected volume is already on $target. Nothing to do."; exit 0; }
echo; printf '%-42s %-22s %-26s %-9s %-9s %s\n' VOLUME NAMESPACE PVC STATE HEALTH FROM
while IFS=$'\t' read -r n s p st r f; do printf '%-42s %-22s %-26s %-9s %-9s %s\n' "$n" "$s" "$p" "$st" "$r" "${f##*:}"; done <<<"$plan"
echo
if [ "$apply" -ne 1 ]; then echo "Dry run. Re-run with --apply (try --volume <one> first)."; exit 0; fi

# ---- run
done_n=0; skipped=()
while IFS=$'\t' read -r name vns pvc st rob from; do
  echo "== $name ($vns/$pvc, $st, $rob)"
  if [ "$st" = detached ]; then
    kubectl create --raw "$proxy/volumes/$name?action=engineUpgrade" -f <(jq -n --arg i "$target" '{image:$i}') >/dev/null
    echo "    detached: image set, takes effect on the next attach"; done_n=$((done_n+1)); continue
  fi
  if [ "$st" != attached ] || [ "$rob" != healthy ]; then
    echo "    SKIPPED: $st / $rob (only attached and healthy volumes are upgraded live)"; skipped+=("$name"); continue
  fi
  run_gate "$vns" before || exit 1
  kubectl create --raw "$proxy/volumes/$name?action=engineUpgrade" -f <(jq -n --arg i "$target" '{image:$i}') >/dev/null
  end=$((SECONDS + timeout)); why="not started"
  while [ $SECONDS -lt $end ]; do
    why="$(unsettled "$name" "$target")"; [ -z "$why" ] && break; sleep 3
  done
  if [ -n "$why" ]; then echo "    STOPPED: $name did not settle in ${timeout}s: $why" >&2; exit 1; fi
  run_gate "$vns" after || exit 1
  echo "    done in $((timeout - (end - SECONDS)))s"; done_n=$((done_n+1))
done <<<"$plan"

echo; echo "$done_n volume(s) on $target.${skipped:+ Skipped: ${skipped[*]}}"
left="$(kubectl get engineimages.longhorn.io -n "$ns" -o json | jq -r --arg i "$target" '.items[] | select(.spec.image != $i and .status.refCount == 0) | .metadata.name')"
[ -z "$left" ] || echo "Old engine image(s) with no references left: $left. Remove with: kubectl delete engineimages.longhorn.io -n $ns <name>"
