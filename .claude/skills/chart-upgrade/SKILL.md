---
name: chart-upgrade
description: Upgrade an Argo CD Helm application to a newer chart version safely: choose what is behind, render and diff old against new, flag the dangerous changes, back up, bump the version in git, sync through the parent app, verify. Use for any chart or app version bump in this repo. NOT for a broken app (use the k8s-diagnostics agent), NOT for a first-time onboarding (use add-gitops-app), NOT for forcing a refresh after a push (use argocd-force-sync).
---

Do one app at a time. Never push or sync without the user's go-ahead.

1. **Pick what to upgrade.** `scripts/chart-outdated.py` lists apps behind, ordered by risk tier
   (routine first, Argo CD last). Read the app's row in `docs/app-upgrade-risks.md`: tier 3 and 4 apps
   need a backup and the release notes before anything else.
2. **Read the release notes** between the two versions (the link `chart-outdated.py` prints is the
   chart home; also the upstream project's changelog). Look for removed or renamed values, removed
   ServiceAccounts or bundled charts, new defaults (NetworkPolicies), required order (CRDs first), and
   minimum Kubernetes or other component versions.
3. **Diff.** `scripts/chart-diff.py <app> --new <version>` renders both versions with the values the
   Application really uses and flags: IMMUTABLE selector or volumeClaimTemplates changes (delete the
   workload with `--cascade=orphan` first), CRD changes (over ~200 KB needs `ServerSideApply`; check
   Rancher ownership), NETPOL additions (pin the value off in the Application unless wanted), RBAC GONE,
   HOOKS, VALUES the Application sets that the new chart no longer declares (a renamed key means the
   setting silently stops applying), and every image change. It writes the full diff to a file; read it.
4. **Back up** what the app holds: `scripts/backup-before-upgrade.sh --label <app>-<ver> --namespaces
   <ns> --etcd-save [--ysql-dump DB] [--argocd-export]` (dry run first, then `--apply`). Databases get a
   logical dump; Argo CD gets the export. Longhorn backup names must be unique, which the script handles.
5. **Edit the version** in the Application manifest under `argocd/<namespace>/` (and any value the diff
   said to change). Commit. Ask before pushing.
6. **Sync.** Child changes under `argocd/<ns>/` are picked up only after the parent `platform-<ns>` app
   refreshes: use the `argocd-force-sync` skill on the parent first, then the app. If the first sync
   reports success but every resource says "unchanged" while Argo shows OutOfSync, hard-refresh and sync
   again (stale manifests). CRDs: wait until established before the rest syncs.
7. **Verify.** Pods Ready and the new image running (`kubectl get pods -n <ns> -o wide`, image tags),
   no new Warning events, the app Healthy and Synced, then the app's own check from the risk table
   (certificates renew, GPU seen, DB queries work, volumes healthy). Longhorn: run the engine upgrade
   after the chart (`scripts/longhorn-engine-upgrade.sh`).
8. **Record** it in the vault: the `incident-note` skill for anything that went wrong, and a changelog
   line for the affected app.

Traps that cost time before: StatefulSet selector changes failing the sync; Helm turning an env value
into a boolean (pass it as a string); a Rancher release taking over a chart you manage; a flood of
helm-operation pods hitting the per-node pod limit; new NetworkPolicies blocking scraping.
