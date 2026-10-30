"""End-to-end test of install/uninstall sharing, in a throwaway sandbox.

Simulates the whole setup in a temp dir: a fake shared drive, NixOS
(claude-shared.py), Windows user "windows-user-a" and Windows user "windows-user-b"
(hook.ps1 under pwsh), each with its own fake home, and a fake `claude`
CLI that edits the plugin files the way the real one does. Touches nothing
outside the temp dir.

  nix shell nixpkgs#powershell -c python3 tests/sync_test.py

Without pwsh only the NixOS side runs.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
PWSH = shutil.which("pwsh")

STUB = r'''#!/usr/bin/env python3
# Fake claude: plugin install/uninstall, marketplace add/remove.
import json, os, sys
from pathlib import Path
home = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path(os.environ["HOME"]) / ".claude")
plugins = home / "plugins"
plugins.mkdir(parents=True, exist_ok=True)
def rd(p):
    try: return json.loads((plugins / p).read_text())
    except Exception: return {}
def wr(p, d): (plugins / p).write_text(json.dumps(d))
a = sys.argv[1:]
with open(os.environ["STUB_LOG"], "a") as fh: fh.write(f"{home} {' '.join(a)}\n")
if a[:2] == ["plugin", "install"]:
    d = rd("installed_plugins.json"); d.setdefault("plugins", {})[a[-1]] = [{"installPath": str(plugins / "cache" / a[-1])}]; wr("installed_plugins.json", d)
elif a[:2] in (["plugin", "uninstall"], ["plugin", "remove"]):
    d = rd("installed_plugins.json"); d.setdefault("plugins", {}).pop(a[-1], None); wr("installed_plugins.json", d)
elif a[:3] == ["plugin", "marketplace", "add"]:
    d = rd("known_marketplaces.json"); d[a[-1].split("/")[-1]] = {"source": {"source": "github", "repo": a[-1]}}; wr("known_marketplaces.json", d)
elif a[:3] == ["plugin", "marketplace", "remove"]:
    d = rd("known_marketplaces.json"); d.pop(a[-1], None); wr("known_marketplaces.json", d)
'''

results = []


def check(name, ok, detail=""):
    results.append(ok)
    print(f"{'PASS' if ok else 'FAIL'}  {name}{'' if ok else '  -- ' + detail}")


class World:
    def __init__(self, root):
        self.root = root
        self.shared = root / "shared"
        self.sync = self.shared / "_sync"
        self.sync.mkdir(parents=True)
        (self.shared / "skills").mkdir()
        manifest = json.loads((HERE / "shared.json").read_text())
        # Only what the sharing logic needs; no real plugins or MCP servers.
        manifest.update({"settings": {}, "linuxSettings": {}, "windowsSettings": {}, "mcpServers": {}})
        (self.sync / "shared.json").write_text(json.dumps(manifest))
        shutil.copy(HERE / "hook.ps1", self.sync / "hook.ps1")
        self.bin = root / "bin"
        self.bin.mkdir()
        (self.bin / "claude").write_text(STUB)
        (self.bin / "claude").chmod(0o755)
        self.log = root / "stub.log"
        self.homes = {}
        for who in ("linux", "windows-user-a", "windows-user-b"):
            home = root / who
            self.homes[who] = home
            (home / ".claude" / "plugins").mkdir(parents=True)
            (home / ".claude.json").write_text(json.dumps({"mcpServers": {}}))
            self.write(who, "installed_plugins.json", {"version": 2, "plugins": {}})
            self.write(who, "known_marketplaces.json", {})
            if who == "linux":
                (home / ".claude" / "skills").mkdir()
            else:  # Windows: ~\.claude\skills is a junction to the shared folder
                (home / ".claude" / "skills").symlink_to(self.shared / "skills")

    def env(self, who, **extra):
        env = dict(os.environ, HOME=str(self.homes[who]), STUB_LOG=str(self.log),
                   PATH=f"{self.bin}:{os.environ['PATH']}", CLAUDE_SHARED_FOREGROUND="1")
        env.pop("CLAUDE_CONFIG_DIR", None)
        env.pop("CLAUDE_SHARED_OFF", None)
        if who != "linux":
            env.update(USERPROFILE=str(self.homes[who]), USERNAME=who)
        env.update(extra)
        return env

    def linux_cmd(self, *args):
        return [sys.executable, str(HERE / "claude-shared.py"), "--shared", str(self.shared),
                "--manifest", str(self.sync / "shared.json"),
                "--claude-dir", str(self.homes["linux"] / ".claude"), "--home", str(self.homes["linux"]), *args]

    def run(self, who, *flags, **env):
        """One session start for `who`."""
        if who == "linux":
            cmd = self.linux_cmd(*(flags or ("hook",)))
        else:
            cmd = [PWSH, "-NoProfile", "-File", str(self.sync / "hook.ps1"), *flags]
        p = subprocess.run(cmd, input="{}", text=True, capture_output=True, env=self.env(who, **env))
        if p.returncode:
            print(p.stdout, p.stderr)
        return p.stdout + p.stderr

    def everyone(self):
        return ["linux", "windows-user-a", "windows-user-b"] if PWSH else ["linux"]

    def round(self, times=1):
        for _ in range(times):
            for who in self.everyone():
                self.run(who)

    # ── fake installs ──
    def read(self, who, name):
        return json.loads((self.homes[who] / ".claude" / "plugins" / name).read_text())

    def write(self, who, name, data):
        (self.homes[who] / ".claude" / "plugins" / name).write_text(json.dumps(data))

    def plugins(self, who):
        return set(self.read(who, "installed_plugins.json").get("plugins", {}))

    def claude(self, who, *args):
        subprocess.run([str(self.bin / "claude"), *args], check=True, env=self.env(who))

    def mcp(self, who):
        return set(json.loads((self.homes[who] / ".claude.json").read_text()).get("mcpServers", {}))

    def set_mcp(self, who, servers):
        path = self.homes[who] / ".claude.json"
        data = json.loads(path.read_text())
        data["mcpServers"] = servers
        path.write_text(json.dumps(data))

    def skill_visible(self, who, name):
        return (self.homes[who] / ".claude" / "skills" / name / "SKILL.md").is_file()

    def add_shared_skill(self, name):
        d = self.shared / "skills" / name
        d.mkdir()
        (d / "SKILL.md").write_text(f"---\nname: {name}\n---\n")

    def registry_lines(self):
        p = self.sync / "registry.jsonl"
        return p.read_text().splitlines() if p.exists() else []


def main():
    if not PWSH:
        print("pwsh not found: testing the NixOS side only (nix shell nixpkgs#powershell for all three)")
    tmp = Path(tempfile.mkdtemp(prefix="claude-sync-test-"))
    w = World(tmp)
    try:
        everyone = w.everyone()
        others = everyone[1:]
        w.round()  # first sessions everywhere: baseline, nothing to do

        # 1. install on NixOS spreads everywhere
        w.claude("linux", "plugin", "marketplace", "add", "acme/mkt")
        w.claude("linux", "plugin", "install", "--scope", "user", "tool@mkt")
        w.round(2)
        check("install on NixOS reaches every OS/user", all("tool@mkt" in w.plugins(x) for x in everyone),
              str({x: w.plugins(x) for x in everyone}))

        # 2. uninstall on one machine spreads everywhere, and stays uninstalled
        remover = "windows-user-a" if PWSH else "linux"
        w.claude(remover, "plugin", "uninstall", "--scope", "user", "tool@mkt")
        w.round(3)
        check(f"uninstall on {remover} removes it everywhere", all("tool@mkt" not in w.plugins(x) for x in everyone),
              str({x: w.plugins(x) for x in everyone}))

        # 3. reinstall anywhere brings it back everywhere
        reinstaller = "windows-user-b" if PWSH else "linux"
        w.claude(reinstaller, "plugin", "install", "--scope", "user", "tool@mkt")
        w.round(2)
        check(f"reinstall on {reinstaller} brings it back everywhere", all("tool@mkt" in w.plugins(x) for x in everyone),
              str({x: w.plugins(x) for x in everyone}))

        # 4. MCP servers: add spreads, removal spreads
        w.set_mcp("linux", {"docs": {"type": "http", "url": "https://example.com/mcp"}})
        w.round(2)
        check("MCP server added on NixOS reaches everyone", all("docs" in w.mcp(x) for x in everyone),
              str({x: w.mcp(x) for x in everyone}))
        w.set_mcp(everyone[-1], {})
        w.round(2)
        check(f"MCP server removed on {everyone[-1]} is removed everywhere", all("docs" not in w.mcp(x) for x in everyone),
              str({x: w.mcp(x) for x in everyone}))

        # 5. skills: removed on NixOS -> gone from the shared folder (in trash), never relinked
        w.add_shared_skill("demo")
        w.round()
        check("skill added to the shared folder is visible everywhere", all(w.skill_visible(x, "demo") for x in everyone))
        (w.homes["linux"] / ".claude" / "skills" / "demo").unlink()
        w.round(2)
        trash = list((w.sync / "trash" / "skills").glob("demo@*"))
        check("skill removed on NixOS is gone everywhere and kept in trash",
              not any(w.skill_visible(x, "demo") for x in everyone) and len(trash) == 1, f"trash={trash}")

        # 6. skills: removed on Windows (deleted from the shared folder) -> NixOS link goes too
        if PWSH:
            w.add_shared_skill("demo2")
            w.round()
            shutil.rmtree(w.shared / "skills" / "demo2")
            w.round(2)
            link = w.homes["linux"] / ".claude" / "skills" / "demo2"
            removed = any('"demo2"' in line and '"removed": true' in line.replace('":true', '": true') for line in w.registry_lines())
            check("skill deleted on Windows is recorded and NixOS drops its link", removed and not os.path.lexists(link))

        # 7. a wiped config is NOT spread (held), and --restore brings it back
        for i in range(12):
            w.add_shared_skill(f"bulk{i}")
        w.round()
        for i in range(12):
            (w.homes["linux"] / ".claude" / "skills" / f"bulk{i}").unlink()
        out = w.run("linux")
        w.round()
        check("12 skills vanishing at once is held, not spread",
              all((w.shared / "skills" / f"bulk{i}").is_dir() for i in range(12)) and "removals --confirm" in out, out[-300:])
        w.run("linux", "removals", "--restore")
        w.run("linux")
        check("removals --restore relinks them", all(w.skill_visible("linux", f"bulk{i}") for i in range(12)))

        # 8. unreadable installed_plugins.json is not "everything uninstalled"
        before = len(w.registry_lines())
        p = w.homes["linux"] / ".claude" / "plugins" / "installed_plugins.json"
        good = p.read_text()
        p.write_text('{"plugins": {"tool@mk')  # half-written
        w.run("linux")
        p.write_text(good)
        w.round()
        check("corrupt plugin list on NixOS removes nothing anywhere",
              len(w.registry_lines()) == before and all("tool@mkt" in w.plugins(x) for x in everyone))

        # 9. power cut mid-append: half-written last line
        with open(w.sync / "registry.jsonl", "a") as fh:
            fh.write('{"at":"x","kind":"plugin","id":"tool@m')
        w.claude("linux", "plugin", "install", "--scope", "user", "extra@mkt")
        w.round(2)
        check("half-written registry line is skipped; later events still work",
              all("extra@mkt" in w.plugins(x) for x in everyone) and all("tool@mkt" in w.plugins(x) for x in everyone))

        # 10. crash between "removed" event and moving the skill to trash
        w.add_shared_skill("crash")
        w.round()
        with open(w.sync / "registry.jsonl", "a") as fh:
            fh.write(json.dumps({"at": "x", "by": "linux:test", "kind": "skill", "id": "crash", "removed": True}) + "\n")
        w.round()
        check("interrupted skill removal is finished next session", not (w.shared / "skills" / "crash").exists()
              and not any(w.skill_visible(x, "crash") for x in everyone))

        # 11. sandbox: hook does nothing, installs there stay there
        before = len(w.registry_lines())
        w.claude("linux", "plugin", "install", "--scope", "user", "local-only@mkt")
        w.run("linux", "hook", CLAUDE_SHARED_OFF="1")
        if PWSH:
            w.claude("windows-user-a", "plugin", "install", "--scope", "user", "local-only@mkt")
            w.run("windows-user-a", CLAUDE_CONFIG_DIR=str(tmp / "elsewhere"))
        check("CLAUDE_SHARED_OFF / other CLAUDE_CONFIG_DIR: nothing recorded", len(w.registry_lines()) == before)
        w.claude("linux", "plugin", "uninstall", "--scope", "user", "local-only@mkt")
        if PWSH:
            w.claude("windows-user-a", "plugin", "uninstall", "--scope", "user", "local-only@mkt")

        box = tmp / "box"
        sandbox_env = w.env("linux", CLAUDE_SANDBOX_DIR=str(box), CLAUDE_SANDBOX_FROM=str(w.homes["linux"] / ".claude"),
                            CLAUDE_SANDBOX_CLAUDE=str(w.bin / "claude"))
        real_before = w.plugins("linux")
        subprocess.run(["bash", str(HERE / "claude-sandbox.sh"), "plugin", "install", "--scope", "user", "trial@mkt"],
                       env=sandbox_env, check=True, capture_output=True)
        subprocess.run(["bash", str(HERE / "claude-sandbox.sh"), "plugin", "uninstall", "--scope", "user", "tool@mkt"],
                       env=sandbox_env, check=True, capture_output=True)
        box_plugins = set(json.loads((box / "plugins" / "installed_plugins.json").read_text())["plugins"])
        w.round(2)
        check("claude-sandbox: install/uninstall there leaves the real setup alone",
              w.plugins("linux") == real_before and "trial@mkt" in box_plugins and "tool@mkt" not in box_plugins
              and all("tool@mkt" in w.plugins(x) and "trial@mkt" not in w.plugins(x) for x in everyone),
              f"real={w.plugins('linux')} box={box_plugins}")
        check("claude-sandbox: plugin paths point into the sandbox, not ~/.claude",
              str(w.homes["linux"] / ".claude" / "plugins") not in (box / "plugins" / "installed_plugins.json").read_text())
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print(f"\n{sum(results)}/{len(results)} passed")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
