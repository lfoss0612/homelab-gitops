#!/usr/bin/env bash
# Is the GPU node healthy after a kernel, driver, GPU operator or Ollama change? Read-only.
#
# Checks: the node advertises the GPU; the GPU operator pods are Running (validators Completed);
# the driver answers nvidia-smi inside the Ollama pod (a driver/library mismatch shows up here);
# Ollama's running version against the tag pinned in git and the latest GitHub release; the model
# list is intact. With --probe MODEL it loads that model with a one-token prompt and checks that
# `ollama ps` says it runs on the GPU. The probe changes nothing on disk but loads the model into
# GPU memory (and may unload another), so it is opt-in.
#
# Not checked here: that DKMS built the NVIDIA module for the kernel that will boot. That is a host
# check; playbooks/fleet-reboot.yml in homelab-ansible asserts it before any reboot, and after a
# release upgrade run `dkms status` on the GPU node.
#
# Usage: scripts/gpu-check.sh [--probe MODEL] [--node NAME] [--namespace NS] [--deployment NAME]
# Exit status 0 when every check passed, 1 otherwise. Needs kubectl, jq, curl.
set -uo pipefail
node=k8s-worker-2.home.lan; ns=open-webui; dep=open-webui-ollama; probe=""
while [ $# -gt 0 ]; do
  case "$1" in
    --probe) probe="${2:?}"; shift 2 ;; --node) node="${2:?}"; shift 2 ;;
    --namespace) ns="${2:?}"; shift 2 ;; --deployment) dep="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,/^set -/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
fail=0
ok()  { printf '  ok    %s\n' "$*"; }
bad() { printf '  FAIL  %s\n' "$*"; fail=1; }
note(){ printf '  note  %s\n' "$*"; }
ex() { kubectl exec -n "$ns" "deploy/$dep" -- sh -c "$1" 2>&1; }

echo "Node $node"
gpus="$(kubectl get node "$node" -o jsonpath='{.status.allocatable.nvidia\.com/gpu}' 2>/dev/null)"
[ "${gpus:-0}" -ge 1 ] 2>/dev/null && ok "advertises $gpus GPU(s)" || bad "no nvidia.com/gpu allocatable (driver or device plugin down)"
kubectl get node "$node" --no-headers 2>/dev/null | grep -q ' Ready' && ok "node Ready" || bad "node not Ready"

echo "GPU operator"
pods="$(kubectl get pods -n gpu-operator --no-headers 2>/dev/null)"
badpods="$(awk '$3!="Running" && $3!="Completed"{print $1" "$3}' <<<"$pods")"
[ -z "$badpods" ] && ok "$(wc -l <<<"$pods") pods Running or Completed" || bad "pods not healthy: $badpods"

echo "Driver (inside $dep)"
smi="$(ex 'nvidia-smi --query-gpu=name,driver_version,memory.used,memory.total --format=csv,noheader')"
if [ $? -eq 0 ] && ! grep -qi 'mismatch\|failed\|error' <<<"$smi"; then ok "nvidia-smi: $smi"; else bad "nvidia-smi: $smi"; fi

echo "Ollama"
running="$(ex 'ollama --version' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
pinned="$(kubectl get deploy -n "$ns" "$dep" -o jsonpath='{.spec.template.spec.containers[0].image}' | sed 's/.*://')"
latest="$(curl -s -m 15 https://api.github.com/repos/ollama/ollama/releases/latest | jq -r '.tag_name // empty' | sed 's/^v//')"
[ -n "$running" ] && ok "running $running (image tag $pinned)" || bad "could not read the Ollama version"
if [ -n "$latest" ] && [ "$latest" != "$running" ]; then
  newest="$(printf '%s\n%s\n' "$running" "$latest" | sort -V | tail -1)"
  [ "$newest" = "$latest" ] && note "newer release $latest available (bump ollama.image.tag in argocd/open-webui/open-webui.yaml; read the release notes, models volume is not backed up)"
fi
models="$(ex 'ollama list' | tail -n +2 | grep -c .)"
[ "$models" -ge 1 ] && ok "$models model(s) listed" || bad "model list is empty (models volume missing?)"

if [ -n "$probe" ]; then
  echo "Probe $probe"
  out="$(ex "ollama run $probe --keepalive 2m 'Reply with the single word ok.' </dev/null")"
  [ $? -eq 0 ] && ok "answered" || bad "run failed: ${out:0:200}"
  ps="$(ex 'ollama ps' | tail -n +2)"
  if grep -q '100% GPU' <<<"$ps"; then ok "on GPU: $ps"; else bad "not fully on the GPU: ${ps:-nothing loaded}"; fi
fi
[ "$fail" -eq 0 ] && echo "GPU node healthy." || echo "GPU node has problems."
exit "$fail"
