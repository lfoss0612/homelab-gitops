#!/usr/bin/env python3
"""Render an Argo CD Helm app at two chart versions and flag what is dangerous in the difference.

Read-only: nothing is applied. Needs kubectl (to read the live Application) and helm.

Usage:
  scripts/chart-diff.py <app> <old-version> <new-version>
  scripts/chart-diff.py longhorn 1.13.0 1.13.1
  scripts/chart-diff.py <app> --new 1.14.0        # old = what the Application pins today

It renders both versions with the values the Application really uses (its helm parameters and inline
values, release name, namespace, CRDs included) and reports:

  IMMUTABLE   a Deployment/StatefulSet/DaemonSet selector, or a StatefulSet volumeClaimTemplates or
              serviceName, changed. The sync will fail; delete the workload with --cascade=orphan
              first, then sync.
  CRD         a CustomResourceDefinition was added or changed; one over ~200 KB needs ServerSideApply
              (the client-side annotation limit is 256 KB). Check ownership if Rancher manages it.
  NETPOL      a NetworkPolicy appears. Charts often switch these on by default; if you do not want them
              pin the value off in the Application.
  RBAC GONE   a ServiceAccount, Role, ClusterRole or binding that existed is no longer rendered. Anything
              that referenced it (a plan, a hand-made object) breaks.
  HOOKS       Helm hooks (Jobs that run before or after the sync) added or removed.
  VALUES      a value the Application sets is not declared in the new chart's default values (renamed
              or removed), so the setting would silently do nothing. Free-form maps are noted, not failed.
  IMAGES      every image that changes, to check against the release notes and the registry.

Plain text parsing of helm's regular output (no YAML library), so it is a flag-raiser, not a proof:
read the full diff it writes (path printed at the end) before syncing. Rendered output can contain
secrets from your values: the directory is mode 700 and outside git.
"""
import argparse
import difflib
import json
import os
import re
import subprocess
import sys
import tempfile

WORKLOADS = ("Deployment", "StatefulSet", "DaemonSet")
RBAC = ("ServiceAccount", "Role", "ClusterRole", "RoleBinding", "ClusterRoleBinding")


def run(cmd, env=None, check=True):
    p = subprocess.run(cmd, capture_output=True, text=True, env=env)
    if check and p.returncode != 0:
        raise SystemExit(f"error: {' '.join(cmd[:3])}...: {p.stderr.strip()[:400]}")
    return p.stdout


def split_docs(text):
    docs = {}
    for d in re.split(r"^---\s*$", text, flags=re.M):
        kind = re.search(r"^kind:\s*(\S+)", d, re.M)
        if not kind:
            continue
        name = re.search(r"^metadata:\n(?:  .*\n)*?  name:\s*\"?([^\"\n]+)\"?", d, re.M)
        ns = re.search(r"^metadata:\n(?:  .*\n)*?  namespace:\s*\"?([^\"\n]+)\"?", d, re.M)
        key = f"{kind.group(1)}/{ns.group(1) if ns else '-'}/{name.group(1).strip() if name else '?'}"
        docs[key] = d.strip("\n")
    return docs


def block(doc, indent, key):
    """Lines of the mapping value under `<indent spaces><key>:` up to the next line at the same or lower indent."""
    out, grab = [], False
    pad = " " * indent
    for line in doc.split("\n"):
        if not grab:
            if re.match(rf"^{pad}{re.escape(key)}:", line):
                grab = True
                out.append(line.strip())
            continue
        if line.strip() == "":
            continue
        if len(line) - len(line.lstrip()) <= indent:
            break
        out.append(line.strip())
    return out


def value_paths(text):
    """Set of dotted key paths declared in a values file (block mappings only), plus the ones with no children."""
    paths, leaves, stack = set(), set(), []
    for raw in text.split("\n"):
        if not raw.strip() or raw.lstrip().startswith("#") or raw.lstrip().startswith("- "):
            continue
        m = re.match(r'^(\s*)("?[A-Za-z0-9_.\-/]+"?):(.*)$', raw)
        if not m:
            continue
        ind, key, rest = len(m.group(1)), m.group(2).strip('"'), m.group(3).strip()
        while stack and stack[-1][0] >= ind:
            stack.pop()
        stack.append((ind, key))
        path = ".".join(k for _, k in stack)
        paths.add(path)
        if rest and not rest.startswith("#"):
            leaves.add(path)
    return paths, leaves


def helm_chart_ref(src, env):
    repo, chart = src["repoURL"], src["chart"]
    if repo.startswith("http"):
        run(["helm", "repo", "add", "src", repo, "--force-update"], env)
        return ["src/" + chart], []
    return [f"oci://{repo}/{chart}"], []


def render(ref, version, app, ns, release, params, valfile, env, extra):
    cmd = ["helm", "template", release, *ref, "--version", version, "--namespace", ns, "--include-crds"]
    for p in params:
        cmd += ["--set", f"{p['name']}={p['value']}"]
    if valfile:
        cmd += ["-f", valfile]
    return run(cmd + extra, env)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("app")
    ap.add_argument("old", nargs="?")
    ap.add_argument("new", nargs="?")
    ap.add_argument("--new", dest="new_opt")
    args = ap.parse_args()
    app = json.loads(run(["kubectl", "get", "applications.argoproj.io", args.app, "-n", "argocd", "-o", "json"]))
    src = app["spec"].get("source") or app["spec"]["sources"][0]
    if not src.get("chart"):
        raise SystemExit(f"error: {args.app} is not a chart from a Helm repository (path {src.get('path')}); diff it with git instead")
    if args.new_opt:
        old, new = args.old or src["targetRevision"], args.new_opt
    elif args.old and args.new:
        old, new = args.old, args.new
    else:
        raise SystemExit("error: give <old> <new>, or --new <version>")
    if old == new:
        raise SystemExit("error: old and new are the same")

    tmp = tempfile.mkdtemp(prefix="chart-diff-")
    os.chmod(tmp, 0o700)
    env = dict(os.environ, HELM_REPOSITORY_CONFIG=f"{tmp}/repos.yaml", HELM_REPOSITORY_CACHE=f"{tmp}/cache",
               HELM_CONFIG_HOME=f"{tmp}/config", HELM_CACHE_HOME=f"{tmp}/hcache")
    ref, _ = helm_chart_ref(src, env)
    helm = src.get("helm", {})
    params = helm.get("parameters", [])
    valfile = None
    if helm.get("values"):
        valfile = f"{tmp}/app-values.yaml"
        open(valfile, "w").write(helm["values"])
    ns = app["spec"]["destination"]["namespace"]
    release = helm.get("releaseName", args.app)
    skipped = helm.get("valueFiles", [])

    print(f"{args.app}: {src['chart']} {old} -> {new}  (release {release}, namespace {ns}, "
          f"{len(params)} parameter(s){', inline values' if valfile else ''})")
    if skipped:
        print(f"NOTE valueFiles {skipped} are not applied here; the render may differ from the live one")
    docs_old = split_docs(render(ref, old, args.app, ns, release, params, valfile, env, []))
    docs_new = split_docs(render(ref, new, args.app, ns, release, params, valfile, env, []))
    flags = 0

    def flag(tag, msg):
        nonlocal flags
        flags += 1
        print(f"  {tag:<10} {msg}")

    added = sorted(set(docs_new) - set(docs_old))
    removed = sorted(set(docs_old) - set(docs_new))
    changed = sorted(k for k in set(docs_old) & set(docs_new) if docs_old[k] != docs_new[k])
    print(f"\n{len(docs_new)} objects now: {len(added)} added, {len(removed)} removed, {len(changed)} changed\n")

    for k in sorted(set(docs_old) & set(docs_new)):
        kind = k.split("/")[0]
        if kind in WORKLOADS:
            fields = [(2, "selector")] + ([(2, "volumeClaimTemplates"), (2, "serviceName")] if kind == "StatefulSet" else [])
            for ind, f in fields:
                if block(docs_old[k], ind, f) != block(docs_new[k], ind, f):
                    flag("IMMUTABLE", f"{k}: spec.{f} changed -> delete with --cascade=orphan before the sync")
    for k in added + changed:
        if k.startswith("CustomResourceDefinition/"):
            size = len(docs_new[k])
            flag("CRD", f"{k} {'added' if k in added else 'changed'} ({size // 1024} KB)"
                 + ("  -> over ~200 KB: needs ServerSideApply" if size > 200_000 else ""))
    for k in added:
        if k.startswith("NetworkPolicy/"):
            flag("NETPOL", f"{k} is new -> pin the chart value off if you do not want it")
    for k in removed:
        if k.split("/")[0] in RBAC:
            flag("RBAC GONE", f"{k} is no longer rendered; check what referenced it")
    hook = lambda d: "helm.sh/hook" in d
    for k in added:
        if hook(docs_new[k]):
            flag("HOOKS", f"{k} added (runs during the sync)")
    for k in removed:
        if hook(docs_old[k]):
            flag("HOOKS", f"{k} removed")

    # Values the Application sets that the new chart no longer declares.
    new_vals = run(["helm", "show", "values", *ref, "--version", new], env)
    paths, leaves = value_paths(new_vals)
    mine = [re.sub(r"\[\d+\]", "", p["name"]) for p in params]
    if helm.get("values"):
        mine += sorted(value_paths(helm["values"])[1])
    for key in sorted(set(mine)):
        if key in paths:
            continue
        parent = ".".join(key.split(".")[:-1])
        if parent and parent in paths:
            # The section still exists, so this is either a free-form entry (gflags, annotations)
            # or a removed key; a text parser cannot tell, so it is a note and not a flag.
            print(f"  {'VALUES?':<10} {key}: {parent} exists but does not declare this key (free-form entry, or removed; check the notes)")
        else:
            flag("VALUES", f"{key}: its section {parent or '(top level)'} is not in {new}'s default values -> renamed or removed; the setting may do nothing")

    def images(docs):
        out = {}
        for k, d in docs.items():
            if k.split("/")[0] in WORKLOADS + ("Job", "CronJob", "Pod"):
                out[k] = sorted(set(re.findall(r"image:\s*\"?([^\"\s]+)", d)))
        return out

    io, inw = images(docs_old), images(docs_new)
    img_changes = [(k, io.get(k, []), v) for k, v in inw.items() if io.get(k) != v]
    if img_changes:
        print("\nImages that change:")
        for k, a, b in img_changes:
            print(f"  {k}\n    {', '.join(a) or '(new)'}\n -> {', '.join(b)}")

    out = os.path.join(tmp, "rendered.diff")
    with open(out, "w") as f:
        for k in changed + added + removed:
            f.writelines(difflib.unified_diff((docs_old.get(k, "") + "\n").splitlines(True), (docs_new.get(k, "") + "\n").splitlines(True),
                                              fromfile=f"{k} @ {old}", tofile=f"{k} @ {new}"))
    print(f"\n{flags} flag(s). Full rendered diff: {out}")
    if flags == 0:
        print("Nothing in the dangerous classes; still read the release notes.")


if __name__ == "__main__":
    main()
