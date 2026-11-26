#!/usr/bin/env python3
"""List every Argo CD Helm application whose chart is behind the latest in its repository.

Read-only. Needs kubectl (to read the Applications) and helm (to read the chart repositories);
no other Python packages. Repositories are added to a throw-away helm config, so your own
`helm repo` list is not touched.

Usage:
  scripts/chart-outdated.py            only apps that are behind, ordered by risk tier
  scripts/chart-outdated.py --all      every Helm app, including the ones that are current
  scripts/chart-outdated.py --json     machine-readable

The order is the order to upgrade in: tier 1 (routine) first, tier 4 (Argo CD itself) last. Tiers and
the care each app needs come from docs/app-upgrade-risks.md, the same table the chart-upgrade skill
points at. An app that is not in that table is tier 2 and is flagged so the table gets a row.

"Jump" says how big the step is: patch, minor or MAJOR (first number changes). A MAJOR jump, or
any jump on a tier 3 or 4 app, means read the release notes before touching it. The link is the
chart's own home page from its repository index.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
RISK_TABLE = os.path.join(HERE, "..", "docs", "app-upgrade-risks.md")
PRERELEASE = re.compile(r"-(rc|alpha|beta|dev|pre|snapshot)", re.I)


def run(cmd, env=None):
    p = subprocess.run(cmd, capture_output=True, text=True, env=env)
    if p.returncode != 0:
        raise RuntimeError(f"{' '.join(cmd[:3])}: {p.stderr.strip()[:200]}")
    return p.stdout


def vkey(v):
    """Sort key for chart versions: all the numbers, so 110.0.2+up80.9.1 and v1.21.3 both work."""
    return tuple(int(x) for x in re.findall(r"\d+", v))


def jump(cur, new):
    a, b = vkey(cur), vkey(new)
    if a == b:
        return "current"
    if a[:1] != b[:1]:
        return "MAJOR"
    if a[:2] != b[:2]:
        return "minor"
    return "patch"


def risk_table():
    """app name -> (tier, note), read from the markdown table in docs/app-upgrade-risks.md."""
    table = {}
    try:
        for line in open(RISK_TABLE, encoding="utf-8"):
            m = re.match(r"\|\s*`([^`]+)`\s*\|\s*([1-4]|-)\s*\|\s*(.*?)\s*\|\s*$", line)
            if m:
                # tier "-" = pinned to another component (version follows it): not reported as behind
                table[m.group(1)] = (0 if m.group(2) == "-" else int(m.group(2)), m.group(3))
    except OSError:
        pass
    return table


def latest_http(repo_url, chart, helm_env, aliases):
    alias = aliases.setdefault(repo_url, f"r{len(aliases)}")
    if alias not in helm_env["added"]:
        run(["helm", "repo", "add", alias, repo_url, "--force-update"], helm_env["env"])
        helm_env["added"].add(alias)
    out = json.loads(run(["helm", "search", "repo", f"{alias}/{chart}", "--versions", "-o", "json"], helm_env["env"]) or "[]")
    out = [o for o in out if o["name"] == f"{alias}/{chart}" and not PRERELEASE.search(o["version"].split("+")[0])]
    if not out:
        return None, None, None
    best = max(out, key=lambda o: vkey(o["version"]))
    home = ""
    try:
        show = run(["helm", "show", "chart", f"{alias}/{chart}", "--version", best["version"]], helm_env["env"])
        m = re.search(r"^home:\s*(\S+)", show, re.M)
        home = m.group(1) if m else ""
    except RuntimeError:
        pass
    return best["version"], best.get("app_version", ""), home


def latest_oci(repo_url, chart):
    """Tags of an OCI chart on ghcr.io (anonymous pull token)."""
    host, _, path = repo_url.partition("/")
    if host != "ghcr.io":
        return None, None, None
    repo = f"{path}/{chart}"
    tok = json.load(urllib.request.urlopen(f"https://ghcr.io/token?scope=repository:{repo}:pull", timeout=20))["token"]
    tags, url = [], f"https://ghcr.io/v2/{repo}/tags/list?n=1000"
    while url:  # the registry pages its answer; the Link header names the next page
        req = urllib.request.Request(url, headers={"Authorization": f"Bearer {tok}"})
        resp = urllib.request.urlopen(req, timeout=20)
        tags += json.load(resp).get("tags", [])
        m = re.search(r'<([^>]+)>;\s*rel="next"', resp.headers.get("Link", ""))
        url = ("https://ghcr.io" + m.group(1)) if m else None
    tags = [t for t in tags if re.match(r"^v?\d+(\.\d+)+$", t)]
    return (max(tags, key=vkey) if tags else None), "", f"https://github.com/{path}"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--all", action="store_true", help="also list apps that are current")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    apps = json.loads(run(["kubectl", "get", "applications.argoproj.io", "-n", "argocd", "-o", "json"]))["items"]
    risks = risk_table()
    tmp = tempfile.mkdtemp(prefix="chart-outdated-")
    env = dict(os.environ, HELM_REPOSITORY_CONFIG=f"{tmp}/repos.yaml", HELM_REPOSITORY_CACHE=f"{tmp}/cache",
               HELM_CONFIG_HOME=f"{tmp}/config", HELM_CACHE_HOME=f"{tmp}/hcache")
    helm_env = {"env": env, "added": set()}
    aliases = {}
    rows, local, follows = [], [], []

    for a in apps:
        name = a["metadata"]["name"]
        src = a["spec"].get("source") or (a["spec"].get("sources") or [{}])[0]
        chart, repo = src.get("chart"), src.get("repoURL", "")
        if not chart:
            if src.get("path", "").startswith("charts/"):
                local.append(f"{name} ({src['path']})")
            continue
        target = src.get("targetRevision", "")
        resolved = (a.get("status", {}).get("sync", {}) or {}).get("revision", "")
        cur = target if re.match(r"^v?\d", target or "") else resolved
        try:
            if repo.startswith("http"):
                new, appv, home = latest_http(repo, chart, helm_env, aliases)
            else:
                new, appv, home = latest_oci(repo, chart)
        except Exception as e:  # keep going: one unreachable repo should not hide the rest
            rows.append({"app": name, "chart": chart, "current": cur, "latest": None, "jump": f"error: {e}", "tier": 2, "note": "", "home": ""})
            continue
        tier, note = risks.get(name, (2, "NOT IN docs/app-upgrade-risks.md - add a row"))
        if tier == 0:
            follows.append(f"{name} ({note})")
            continue
        j = jump(cur, new) if (new and cur) else "unknown"
        rows.append({"app": name, "chart": chart, "current": cur, "latest": new, "app_version": appv, "jump": j, "tier": tier, "note": note, "home": home})

    rows.sort(key=lambda r: (r["tier"], r["app"]))
    shown = [r for r in rows if args.all or r["jump"] not in ("current",)]
    if args.json:
        print(json.dumps({"apps": shown, "local_charts": local, "follows_another_component": follows}, indent=2))
        return
    print(f"{'TIER':<5}{'APP':<28}{'CURRENT':<30}{'LATEST':<30}{'JUMP':<8}NOTE")
    for r in shown:
        flag = " <- read the release notes" if r["jump"] == "MAJOR" or (r["tier"] >= 3 and r["jump"] not in ("current", "unknown")) else ""
        print(f"{r['tier']:<5}{r['app']:<28}{(r['current'] or '?'):<30}{(r['latest'] or '?'):<30}{r['jump']:<8}{r['note']}{flag}")
        if r["home"] and r["jump"] not in ("current",):
            print(f"{'':<5}{'':<28}{r['home']}")
    behind = sum(1 for r in rows if r["jump"] in ("patch", "minor", "MAJOR"))
    print(f"\n{behind} of {len(rows)} Helm apps behind. Charts kept in this repo (not checked): {', '.join(local) or 'none'}.")
    if follows:
        print(f"Not reported (version follows another component): {'; '.join(follows)}.")


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as e:
        sys.exit(f"error: {e}")
