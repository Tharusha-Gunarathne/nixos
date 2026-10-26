"""claude-shared: share Claude Code state between NixOS and Windows.

Shared data lives on an NTFS drive both OSes mount. Windows is canonical:
its ~/.claude/{projects,skills,...} are junctions straight into the shared
dir (see bootstrap.ps1). Linux keeps ~/.claude on ext4 and points into the
shared dir with symlinks, translating Linux project keys
(-mnt-E-Drive-foo) to the Windows keys (E--foo) Claude uses there.

Subcommands:
  sync     full reconcile (run by home-manager activation and the timer)
  prepare  link the project for one directory (run by the claude wrapper)
  hook     SessionStart hook: prepare + skills + cross-OS install registry
  plugins  install plugins/marketplaces declared in shared.json or recorded
           in the registry but missing here, uninstall ones removed elsewhere
  removals show uninstalls held back as suspicious; --confirm spreads them,
           --restore treats them as an accident and brings the items back
  status   show what is linked where

Install registry: _sync/registry.jsonl is an append-only log every OS and
user adds to: an event when a plugin, marketplace or MCP server shows up,
and a removal event when something installed here last time is gone (a
skill, too). Replayed in order, the latest event wins: an uninstall anywhere
uninstalls it everywhere, a reinstall anywhere brings it back everywhere.
Per machine and user, _sync/state remembers what was here last time, which
is how an uninstall here is told apart from "never had it".

Sandboxes (claude-sandbox, CLAUDE_CONFIG_DIR elsewhere, CLAUDE_SHARED_OFF=1)
are left alone: nothing done there is recorded or shared.
"""
import argparse
import filecmp
import getpass
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

# Never move a directory a running session may still be appending to.
QUIET_SECONDS = 30 * 60
# Claude hashes project keys longer than this; we don't reproduce the hash.
MAX_KEY = 200
WINDOWS_ABS = re.compile(r"^[A-Za-z]:[\\/]")
# Commands that need a cmd /c shim on Windows (they are .cmd scripts there).
CMD_SHIMMED = {"npx", "bunx", "pnpm", "yarn", "npm"}
# A failed plugin install is retried at most this often.
RETRY_SECONDS = 24 * 60 * 60
# Marks a shared skill copied from a claude.ai account; holds the source.
ACCOUNT_MARKER = ".account-skill"
# What the registry tracks; "skill" only records removals and reinstalls.
KINDS = ("plugin", "marketplace", "mcp", "skill")
# More uninstalls than this at once are held until confirmed: a wiped or
# reset config looks exactly like "the user uninstalled everything".
MASS_REMOVAL = 10
# Removed shared skills stay in _sync/trash this long.
TRASH_DAYS = 30


def log(msg):
    print(f"claude-shared: {msg}", file=sys.stderr)


def sharing_off(claude_dir):
    """A sandbox (claude-sandbox) or a session with sharing turned off."""
    if os.environ.get("CLAUDE_SHARED_OFF") == "1":
        return True
    config = os.environ.get("CLAUDE_CONFIG_DIR")
    return bool(config) and os.path.realpath(os.path.expanduser(config)) != os.path.realpath(claude_dir)


def encode(path):
    """Claude Code's project key: every non-alphanumeric char becomes '-'."""
    return re.sub(r"[^a-zA-Z0-9]", "-", path)


def find_ci(parent, name):
    """Windows may have created e--foo for E--foo; NTFS treats them as one."""
    exact = parent / name
    if exact.exists():
        return exact
    if parent.is_dir():
        for child in parent.iterdir():
            if child.name.lower() == name.lower():
                return child
    return exact


def recently_active(path):
    cutoff = time.time() - QUIET_SECONDS
    for root, _dirs, files in os.walk(path):
        for f in files:
            try:
                if os.lstat(os.path.join(root, f)).st_mtime > cutoff:
                    return True
            except OSError:
                pass
    return False


def move_file(src, dst):
    # copyfile only: ntfs3 rejects chmod/utime, so no copystat.
    try:
        os.rename(src, dst)
    except OSError:
        shutil.copyfile(src, dst)
        os.unlink(src)


def merge_move(src, dst):
    """Move src's contents into dst without overwriting. Returns leftovers."""
    dst.mkdir(parents=True, exist_ok=True)
    left = 0
    for item in list(src.iterdir()):
        target = find_ci(dst, item.name)
        if item.is_symlink():
            left += 1
        elif item.is_dir():
            left += merge_move(item, target)
            if not any(item.iterdir()):
                item.rmdir()
        elif not target.exists():
            move_file(item, target)
        elif target.is_file() and filecmp.cmp(item, target, shallow=False):
            item.unlink()
        else:
            left += 1
    return left


def copy_tree(src, dst):
    for root, _dirs, files in os.walk(src, followlinks=True):
        out = dst / os.path.relpath(root, src)
        out.mkdir(parents=True, exist_ok=True)
        for f in files:
            shutil.copyfile(os.path.join(root, f), out / f)


def read_json(path):
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def read_json_or_none(path, key=None):
    """Like read_json, but None when the file (or its key) is missing or
    unreadable, so a broken config never reads as "everything uninstalled"."""
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict):
        return None
    if key is None:
        return data
    return data[key] if isinstance(data.get(key), dict) else None


def write_json(path, data):
    tmp = Path(str(path) + ".tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def session_cwd(project_dir):
    """The cwd recorded in a project's newest session transcript."""
    jsonls = sorted(project_dir.glob("*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)
    for jsonl in jsonls:
        try:
            with open(jsonl, encoding="utf-8") as fh:
                for i, line in enumerate(fh):
                    if i > 50:
                        break
                    try:
                        cwd = json.loads(line).get("cwd")
                    except (ValueError, AttributeError):
                        continue
                    if cwd:
                        return cwd
        except OSError:
            continue
    return None


class Shared:
    def __init__(self, args):
        self.claude = Path(args.claude_dir).expanduser()
        self.home = Path(args.home).expanduser()
        self.root = Path(args.shared)
        self.mounts = {}
        for spec in args.map:
            mountpoint, letter = spec.rsplit("=", 1)
            self.mounts[os.path.normpath(mountpoint)] = letter.upper()
        self.manifest = json.loads(Path(args.manifest).read_text(encoding="utf-8"))
        self.hook_command = args.hook_command
        self.skill_updater = args.skill_updater
        self.who = f"linux:{getpass.getuser()}"
        stamp = time.strftime("%Y%m%d-%H%M%S")
        self.backup = self.claude / "backups" / f"pre-shared-{stamp}"

    # ── path translation ────────────────────────────────────────────────
    def mount_of(self, path):
        for mountpoint in self.mounts:
            if path == mountpoint or path.startswith(mountpoint + "/"):
                return mountpoint
        return None

    def to_windows(self, path):
        mountpoint = self.mount_of(path)
        if mountpoint is None:
            return None
        rest = path[len(mountpoint):].strip("/")
        return self.mounts[mountpoint] + ":\\" + rest.replace("/", "\\")

    def from_windows(self, wpath):
        m = re.match(r"^([A-Za-z]):[\\/]?(.*)$", wpath)
        if not m:
            return None
        letter, rest = m.group(1).upper(), m.group(2).replace("\\", "/").strip("/")
        for mountpoint, mapped in self.mounts.items():
            if mapped == letter:
                return mountpoint + ("/" + rest if rest else "")
        return None

    # ── safety ──────────────────────────────────────────────────────────
    def healthy(self):
        mountpoint = self.mount_of(str(self.root))
        if mountpoint is None:
            return True
        if not os.path.ismount(mountpoint):
            log(f"{mountpoint} is not mounted; sessions stay local this time.")
            return False
        if os.statvfs(mountpoint).f_flag & os.ST_RDONLY:
            log(f"{mountpoint} is read-only (Windows Fast Startup/hibernation?); sessions stay local.")
            return False
        return True

    def private_app(self, path, label):
        """Park whatever merge_move could not place, instead of deleting it."""
        if path.is_dir() and not any(path.iterdir()):
            path.rmdir()
            return
        dest = self.backup / label
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(path), str(dest))
        log(f"kept conflicting leftovers of {path} in {dest}")

    def link(self, local, target):
        if local.is_symlink():
            if os.readlink(local) == str(target):
                return
            local.unlink()
        local.symlink_to(target)

    def adopt(self, local, target, label):
        """Move a real local dir into the shared target and link it back."""
        if recently_active(local):
            log(f"skipping {local}: used in the last {QUIET_SECONDS // 60} min")
            return
        merge_move(local, target)
        self.private_app(local, label)
        self.link(local, target)
        log(f"shared {local} -> {target}")

    # ── settings ────────────────────────────────────────────────────────
    def effective_settings(self):
        """Shared settings with the Linux-only block layered on top."""
        overrides = {**self.manifest.get("settings", {})}
        for key, value in self.manifest.get("linuxSettings", {}).items():
            if isinstance(value, dict) and isinstance(overrides.get(key), dict):
                overrides[key] = {**overrides[key], **value}
            elif not key.startswith("_"):
                overrides[key] = value
        # Declared in shared.json but uninstalled somewhere: stays uninstalled.
        _wanted, removed = self.read_registry()
        for key, kind in (("enabledPlugins", "plugin"), ("extraKnownMarketplaces", "marketplace")):
            if isinstance(overrides.get(key), dict):
                overrides[key] = {k: v for k, v in overrides[key].items() if k not in removed.get(kind, ())}
        return overrides

    def merge_settings(self):
        path = self.claude / "settings.json"
        data = read_json(path)
        for key, value in self.effective_settings().items():
            if isinstance(value, dict) and isinstance(data.get(key), dict):
                data[key].update(value)
            else:
                data[key] = value
        if self.hook_command:
            # Runs however claude is launched (headroom wrap, IDE, desktop).
            starts = data.setdefault("hooks", {}).setdefault("SessionStart", [])
            starts[:] = [g for g in starts if not any(
                "claude-shared" in h.get("command", "") for h in g.get("hooks", []))]
            starts.append({"hooks": [{"type": "command", "command": self.hook_command, "timeout": 30}]})
        write_json(path, data)

    def merge_mcp(self):
        """Add this OS's variant of each shared MCP server to ~/.claude.json."""
        _registry, removed = self.read_registry()
        wanted = {name: spec["linux"] for name, spec in self.manifest.get("mcpServers", {}).items()
                  if isinstance(spec, dict) and "linux" in spec and name not in removed.get("mcp", ())}
        if not wanted:
            return
        path = self.home / ".claude.json"
        data = read_json(path)
        servers = data.setdefault("mcpServers", {})
        if all(servers.get(name) == spec for name, spec in wanted.items()):
            return
        servers.update(wanted)
        write_json(path, data)

    # ── plugins ─────────────────────────────────────────────────────────
    def missing(self):
        """Marketplaces and plugins wanted here (shared.json + registry) but absent."""
        settings = self.effective_settings()
        markets = {name: spec.get("source", {}) for name, spec in settings.get("extraKnownMarketplaces", {}).items()}
        plugins = [p for p, on in settings.get("enabledPlugins", {}).items() if on]
        wanted, _removed = self.read_registry()
        for name, specs in wanted.get("marketplace", {}).items():
            source = dict(specs.get("linux") or next(iter(specs.values())))
            if source.get("source") == "directory":
                source["path"] = self.from_windows(source.get("path", ""))
                if not source["path"]:
                    continue  # lives on C:, unreachable from here
            markets.setdefault(name, source)
        plugins += [p for p in wanted.get("plugin", {}) if p not in plugins]
        known = read_json(self.claude / "plugins" / "known_marketplaces.json")
        installed = read_json(self.claude / "plugins" / "installed_plugins.json").get("plugins", {})
        failed = self.read_state().get("failed", {})
        recent = {k for k, at in failed.items() if time.time() - at < RETRY_SECONDS}
        markets = {n: s for n, s in markets.items() if n not in known and n not in recent}
        plugins = [p for p in plugins if p not in installed and p not in recent
                   and p.split("@")[-1] in set(known) | set(markets)]
        return markets, plugins

    def unwanted(self):
        """Plugins and marketplaces installed here that were uninstalled
        elsewhere. Only ones this machine already had: one installed since
        is a reinstall, which the next hook records instead."""
        _wanted, removed = self.read_registry()
        state = self.read_state()
        seen = state.get("seen")
        if not isinstance(seen, dict):
            return [], []
        failed = state.get("failed", {})
        recent = {k for k, at in failed.items() if time.time() - at < RETRY_SECONDS}
        result = []
        for kind, path in (("plugin", "installed_plugins.json"), ("marketplace", "known_marketplaces.json")):
            data = read_json(self.claude / "plugins" / path)
            here = data.get("plugins", {}) if kind == "plugin" else data
            result.append([i for i in here if i in removed.get(kind, ()) and i in seen.get(kind, ())
                           and f"uninstall:{i}" not in recent])
        return result[0], result[1]

    def plugins(self, claude_bin):
        """settings.json only declares plugins; Claude installs nothing by itself."""
        markets, plugins = self.missing()
        failed = []
        gone_plugins, gone_markets = self.unwanted()
        for plugin in gone_plugins:
            log(f"uninstalling plugin {plugin} (uninstalled on another OS or user)")
            if subprocess.run([claude_bin, "plugin", "uninstall", "--scope", "user", plugin], check=False).returncode:
                failed.append(f"uninstall:{plugin}")
        for name in gone_markets:
            log(f"removing marketplace {name} (removed on another OS or user)")
            if subprocess.run([claude_bin, "plugin", "marketplace", "remove", name], check=False).returncode:
                failed.append(f"uninstall:{name}")
        for name, source in markets.items():
            ref = source.get("repo") or source.get("path") or source.get("url")
            if not ref:
                continue
            log(f"adding marketplace {name} ({ref})")
            if subprocess.run([claude_bin, "plugin", "marketplace", "add", ref], check=False).returncode:
                failed.append(name)
        for plugin in plugins:
            log(f"installing plugin {plugin}")
            if subprocess.run([claude_bin, "plugin", "install", "--scope", "user", plugin], check=False).returncode:
                failed.append(plugin)
        state = self.read_state()
        state["failed"] = {k: at for k, at in state.get("failed", {}).items()
                           if time.time() - at < RETRY_SECONDS}
        for item in failed:
            log(f"{item} failed; retrying in {RETRY_SECONDS // 3600}h")
            state["failed"][item] = time.time()
        self.write_state(state)

    # ── cross-OS install registry (_sync/registry.jsonl) ────────────────
    def registry_log(self):
        return self.root / "_sync" / "registry.jsonl"

    def read_registry(self):
        """(wanted, removed), replaying the log in order.

        wanted is {kind: {id: {os: spec}}}; removed is {kind: set of ids}
        whose latest event is a removal. A later add (a reinstall anywhere)
        takes an item off removed again."""
        wanted, removed = {}, {}
        try:
            lines = self.registry_log().read_text(encoding="utf-8").splitlines()
        except OSError:
            return wanted, removed
        for line in lines:
            try:
                event = json.loads(line)
                kind, item_id = event["kind"], event["id"]
                if event.get("removed"):
                    wanted.get(kind, {}).pop(item_id, None)
                    removed.setdefault(kind, set()).add(item_id)
                else:
                    wanted.setdefault(kind, {}).setdefault(item_id, {})[event["os"]] = event.get("spec", {})
                    removed.get(kind, set()).discard(item_id)
            except (ValueError, KeyError, TypeError, AttributeError):
                continue  # half-written line from an interrupted append
        return wanted, removed

    def append_events(self, events):
        if not events:
            return
        path = self.registry_log()
        path.parent.mkdir(parents=True, exist_ok=True)
        # A power cut mid-append can leave a last line without its newline;
        # start on a fresh line so only that one event is lost (and it is
        # re-recorded next run, since it never parsed).
        sep = ""
        if path.exists() and path.stat().st_size:
            with open(path, "rb") as fh:
                fh.seek(-1, os.SEEK_END)
                sep = "" if fh.read(1) == b"\n" else "\n"
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(sep + "\n".join(json.dumps(e) for e in events) + "\n")

    def installed_here(self):
        """{kind: {id: spec}}; a kind is None when its config can't be read."""
        plugins_dir = self.claude / "plugins"
        known = read_json_or_none(plugins_dir / "known_marketplaces.json")
        markets = None
        if known is not None:
            markets = {}
            for name, spec in known.items():
                source = dict(spec.get("source", {})) if isinstance(spec, dict) else {}
                if source.get("source") == "directory":
                    # Registry paths are in Windows form; Linux-only dirs can't be shared.
                    source["path"] = self.to_windows(source.get("path", ""))
                    if not source["path"]:
                        continue
                markets[name] = source
        installed = read_json_or_none(plugins_dir / "installed_plugins.json", "plugins")
        return {
            "plugin": None if installed is None else {p: {} for p in installed},
            "marketplace": markets,
            "mcp": read_json_or_none(self.home / ".claude.json", "mcpServers"),
            "skill": self.skills_here(),
        }

    def skills_here(self):
        """Skill names in ~/.claude/skills. One skill-update is swapping
        (its folder is briefly gone) still counts as here."""
        local_dir = self.claude / "skills"
        if local_dir.is_symlink() or not local_dir.is_dir():
            return None
        exclude = set(self.manifest.get("perEntryExclude", []))
        names = {e.name for e in local_dir.iterdir()
                 if not e.name.startswith(".") and e.name not in exclude and (e.is_symlink() or e.is_dir())}
        names |= {p.name[len("swap-"):-len(".json")] for p in (self.root / "_sync" / "tmp").glob("swap-*.json")}
        return {n: {} for n in names}

    def sync_removals(self, mode=None):
        """Spread uninstalls, then record what is installed here.

        Gone since last time = uninstalled here: recorded as removed for
        every OS and user. Removed elsewhere and still here = uninstalled
        here too (MCP servers and skills now, plugins by `plugins` in the
        background). mode "confirm" lets a held mass removal through;
        "restore" drops it, so the items are reinstalled/relinked instead."""
        wanted, removed = self.read_registry()
        current = self.installed_here()
        state = self.read_state()
        seen = state.get("seen") if isinstance(state.get("seen"), dict) else None
        held_before = state.get("held", {}) if isinstance(state.get("held"), dict) else {}
        stamp = time.strftime("%Y-%m-%dT%H:%M:%S")
        events, record, new_seen, held = [], {}, {}, {}
        drop_mcp, drop_skills = [], []
        for kind in KINDS:
            here = current[kind]
            if here is None:  # unreadable right now: change nothing
                if seen and kind in seen:
                    new_seen[kind] = seen[kind]
                if kind in held_before:
                    held[kind] = held_before[kind]
                continue
            # First run here (or for this kind): nothing counts as uninstalled.
            before = set(seen[kind]) if seen and kind in seen else set(here)
            if mode == "restore":
                before -= set(held_before.get(kind, ()))
            gone = sorted(before - set(here) - removed.get(kind, set()))
            if gone and mode != "confirm" and (len(gone) > MASS_REMOVAL or (len(before) >= 4 and not here)):
                held[kind] = gone
                if gone != held_before.get(kind):
                    log(f"{len(gone)} {kind}(s) disappeared at once; NOT spreading that to other OSes/users. "
                        f"If you meant it: claude-shared removals --confirm (undo: --restore)")
            else:
                for item_id in gone:
                    events.append({"at": stamp, "by": self.who, "kind": kind, "id": item_id, "removed": True})
                    wanted.get(kind, {}).pop(item_id, None)
                    removed.setdefault(kind, set()).add(item_id)
                    log(f"{kind} {item_id} uninstalled here; removing it on every OS and user")
            if kind == "skill":
                # Also finishes a removal a crash interrupted.
                drop_skills += [n for n in before - set(here) if n in removed.get(kind, ())]
            stale = set(here) & before & removed.get(kind, set())
            if kind == "mcp":
                drop_mcp = sorted(stale)
            elif kind == "skill":
                drop_skills += sorted(stale)
            keep = set(here) - stale if kind in ("mcp", "skill") else set(here)
            new_seen[kind] = sorted(keep | set(held.get(kind, ())))
            if kind == "skill":
                # Only reinstalls of a removed skill need an event.
                record[kind] = {n: {} for n in set(here) - before if n in removed.get(kind, ())}
            else:
                record[kind] = {i: spec for i, spec in here.items() if i not in stale}
        for kind, items in record.items():
            for item_id, spec in items.items():
                if wanted.get(kind, {}).get(item_id, {}).get("linux") != spec:
                    events.append({"at": stamp, "by": self.who, "os": "linux", "kind": kind, "id": item_id, "spec": spec})
        # Log first: if the power goes now, the next run finishes the job.
        self.append_events(events)
        if drop_mcp:
            path = self.home / ".claude.json"
            data = read_json_or_none(path)
            if data is not None and isinstance(data.get("mcpServers"), dict):
                for name in drop_mcp:
                    data["mcpServers"].pop(name, None)
                write_json(path, data)
                log(f"removed MCP servers uninstalled elsewhere: {', '.join(drop_mcp)}")
        for name in sorted(set(drop_skills)):
            self.remove_skill(name)
        state = self.read_state()
        state["seen"] = new_seen
        state["held"] = held
        self.write_state(state)

    def remove_skill(self, name):
        local = self.claude / "skills" / name
        if local.is_symlink():
            local.unlink()
        elif local.is_dir():
            self.private_app(local, f"skills/{name}")
        shared = find_ci(self.root / "skills", name)
        if shared.exists() and not shared.is_symlink():
            # Same drive: a rename, so a power cut leaves it in one place or the other.
            trash = self.root / "_sync" / "trash" / "skills" / f"{shared.name}@{time.strftime('%Y%m%d-%H%M%S')}"
            trash.parent.mkdir(parents=True, exist_ok=True)
            os.rename(shared, trash)
            log(f"skill {name} removed everywhere; kept in {trash} for {TRASH_DAYS} days")

    def purge_trash(self):
        cutoff = time.time() - TRASH_DAYS * 86400
        for entry in (self.root / "_sync" / "trash" / "skills").glob("*@*"):
            try:
                at = time.mktime(time.strptime(entry.name.rsplit("@", 1)[1], "%Y%m%d-%H%M%S"))
            except ValueError:
                continue
            if at < cutoff:
                shutil.rmtree(entry, ignore_errors=True)

    def removals(self, mode):
        if mode:
            self.sync_removals(mode)
            if mode == "restore":
                self.link_shared_entries()
        held = self.read_state().get("held") or {}
        if not any(held.values()):
            print("no uninstalls are held")
        for kind, items in held.items():
            print(f"held {kind}: {', '.join(items)}")

    # Per machine and user: what failed or can't run here, so it is
    # reported once instead of on every session.
    def state_file(self):
        return self.root / "_sync" / "state" / f"{self.who.replace(':', '-')}.json"

    def read_state(self):
        return read_json(self.state_file())

    def write_state(self, data):
        self.state_file().parent.mkdir(parents=True, exist_ok=True)
        write_json(self.state_file(), data)

    @staticmethod
    def linux_server(spec):
        """A Windows MCP entry rewritten for Linux, or None if it can't run here."""
        if "url" in spec:
            return spec
        spec = json.loads(json.dumps(spec))
        args = list(spec.get("args", []))
        if str(spec.get("command", "")).lower() in ("cmd", "cmd.exe") and args[:1] == ["/c"] and len(args) > 1:
            spec["command"], spec["args"] = args[1], args[2:]
        command = str(spec.get("command", ""))
        if not command or "\\" in command or "/" in command or command.lower().endswith(".exe"):
            return None
        if any(WINDOWS_ABS.match(str(a)) for a in spec.get("args", [])) or not shutil.which(command):
            return None
        return spec

    def import_mcp(self):
        """Add MCP servers recorded elsewhere that are missing here, when they can run here."""
        wanted = self.read_registry()[0].get("mcp", {})
        if not wanted:
            return
        path = self.home / ".claude.json"
        data = read_json(path)
        servers = data.setdefault("mcpServers", {})
        state = self.read_state()
        reported = set(state.get("mcpUnsupported", []))
        added, unsupported = [], []
        for name, specs in wanted.items():
            if name in servers:
                continue
            converted = specs.get("linux") or next(
                (c for c in map(self.linux_server, specs.values()) if c is not None), None)
            if converted is None:
                unsupported.append(name)
                continue
            servers[name] = converted
            added.append(name)
        if added:
            write_json(path, data)
            log(f"added MCP servers from the registry: {', '.join(added)}")
        for name in sorted(set(unsupported) - reported):
            log(f"MCP server {name} can't run here; add a 'linux' entry for it in shared.json")
        if set(unsupported) != reported:
            state["mcpUnsupported"] = sorted(unsupported)
            self.write_state(state)

    # ── whole-directory links (agents, plans, ...) ──────────────────────
    def sync_link_dirs(self):
        for name in self.manifest.get("linkDirs", []):
            target = self.root / name
            target.mkdir(parents=True, exist_ok=True)
            local = self.claude / name
            if local.is_dir() and not local.is_symlink():
                self.adopt(local, target, name)
            else:
                self.link(local, target)

    # ── links outside ~/.claude (claude-mem's database) ─────────────────
    def sync_home_links(self):
        for local_name, shared_name in self.manifest.get("homeLinkDirs", {}).items():
            target = self.root / shared_name
            target.mkdir(parents=True, exist_ok=True)
            local = self.home / local_name
            if local.is_dir() and not local.is_symlink():
                # A live worker holds the SQLite db open; moving it corrupts it.
                if any(local.glob("*worker.pid")):
                    log(f"skipping {local}: stop the claude-mem worker first (claude-mem stop)")
                    continue
                self.adopt(local, target, shared_name)
            else:
                self.link(local, target)

    # ── per-entry links (skills) ────────────────────────────────────────
    def mirror(self, store_path, dest):
        """Copy a Nix-pinned skill into the shared dir so Windows gets it."""
        marker = dest / ".nix-mirror"
        if dest.exists() and not marker.exists():
            return
        if marker.exists() and marker.read_text(encoding="utf-8") == store_path:
            return
        if dest.exists():
            shutil.rmtree(dest)
        copy_tree(store_path, dest)
        marker.write_text(store_path, encoding="utf-8")

    # ── claude.ai account skills ────────────────────────────────────────
    def local_plugins(self):
        """(plugin names, skill names) provided by locally installed plugins."""
        plugins, skills = set(), set()
        for key, entries in read_json(self.claude / "plugins" / "installed_plugins.json").get("plugins", {}).items():
            plugins.add(key.split("@")[0])
            for entry in entries:
                found = Path(entry.get("installPath", "")) / "skills"
                if found.is_dir():
                    skills.update(p.name for p in found.iterdir())
        return plugins, skills

    def account_skills(self):
        """{shared name: source dir} for skills a claude.ai login syncs in.

        Claude keeps these per account (skills/synced/<org>_<account>,
        plugins/synced/...), so they vanish on switching accounts. Skipped:
        Anthropic's built-ins (every account has them) and anything a locally
        installed plugin already provides.
        """
        have_plugins, have_skills = self.local_plugins()
        found = {}
        for root in (self.claude / "skills" / "synced", self.root / "skills" / "synced"):
            for manifest in sorted(root.glob("*/manifest.json")):
                for skill in read_json(manifest).get("skills", []):
                    name = str(skill.get("name", ""))
                    src = manifest.parent / name
                    if skill.get("source") == "plugin" and name not in have_skills and (src / "SKILL.md").is_file():
                        found.setdefault(name, src)
        for account in sorted((self.claude / "plugins" / "synced").glob("*/")):
            for meta in sorted(account.glob("*.meta.json")):
                plugin = account / meta.name[:-len(".meta.json")]
                name = read_json(plugin / ".claude-plugin" / "plugin.json").get("name") or plugin.name
                if name in have_plugins:
                    continue
                for skill in sorted((plugin / "skills").glob("*/SKILL.md")):
                    # Prefixed: plugin skills have generic names (start, update).
                    found.setdefault(f"{name}-{skill.parent.name}", skill.parent)
        return found

    def sync_account_skills(self):
        """Copy account skills into the shared skills dir so every login,
        user and OS has them. Adds and updates only, never deletes."""
        shared_dir = self.root / "skills"
        removed = self.read_registry()[1].get("skill", set())
        for name, src in self.account_skills().items():
            if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", name):
                continue  # names come from a server manifest; stay inside skills/
            if name in removed:
                continue  # uninstalled somewhere; the account copy doesn't bring it back
            dest = find_ci(shared_dir, name)
            marker = dest / ACCOUNT_MARKER
            if dest.exists() and not marker.exists():
                continue  # an unrelated skill already has this name
            # Content hash: the same skill synced on both OSes has different mtimes.
            digest = hashlib.sha256()
            files = {f.relative_to(src).as_posix(): f for f in src.rglob("*") if f.is_file()}
            for rel in sorted(files):  # ordinal order, matching hook.ps1
                digest.update(rel.encode() + b"\0" + files[rel].read_bytes())
            stamp = digest.hexdigest()
            if marker.exists() and marker.read_text(encoding="utf-8") == stamp:
                continue
            # Marker first (with no hash): an interrupted copy is redone next run.
            dest.mkdir(parents=True, exist_ok=True)
            marker.write_text("copying", encoding="utf-8")
            copy_tree(src, dest)
            marker.write_text(stamp, encoding="utf-8")
            log(f"shared account skill {name}")

    # ── skills linked from elsewhere (npx skills -> ~/.agents/skills) ───
    def share_linked_skills(self):
        """Copy skills that ~/.claude/skills links to outside the shared dir
        (e.g. `npx skills add`, which keeps the real files in ~/.agents) into
        the shared dir, so Windows gets them. '.linked-from' records the
        source (same marker hook.ps1 uses); later updates there flow in on
        the next session. Adds and updates files only, never deletes."""
        shared_dir = self.root / "skills"
        local_dir = self.claude / "skills"
        if local_dir.is_symlink() or not local_dir.is_dir():
            return
        removed = self.read_registry()[1].get("skill", set())
        for entry in sorted(local_dir.iterdir()):
            if not entry.is_symlink() or entry.name.startswith(".") or entry.name in removed:
                continue
            real = os.path.realpath(entry)
            if real.startswith(("/nix/store/", str(self.root) + "/")) or not os.path.isfile(os.path.join(real, "SKILL.md")):
                continue
            dest = find_ci(shared_dir, entry.name)
            marker = dest / ".linked-from"
            if (dest / ".skill-source").exists() and not marker.exists():
                # skill-update found its upstream and keeps the shared copy
                # current; use that instead of the older linked copy (which
                # stays where it is).
                self.link(entry, dest)
                log(f"skill {entry.name} now uses the shared, auto-updated copy")
                continue
            ours = marker.is_file() and marker.read_text(encoding="utf-8").strip() == real
            # .nix-mirror: copied from a skill Nix used to pin; free to take over.
            if dest.exists() and not ours and not (dest / ".nix-mirror").exists():
                continue  # a different skill of this name, or one Windows keeps up to date
            if not ours:
                # Marker first: an interrupted copy is finished next run.
                dest.mkdir(parents=True, exist_ok=True)
                marker.write_text(real, encoding="utf-8")
            changed = 0
            for root, _dirs, files in os.walk(real, followlinks=True):
                out = dest / os.path.relpath(root, real)
                out.mkdir(parents=True, exist_ok=True)
                for f in files:
                    src = os.path.join(root, f)
                    if not (out / f).is_file() or not filecmp.cmp(src, out / f, shallow=False):
                        shutil.copyfile(src, out / f)
                        changed += 1
            if changed:
                log(f"skill {entry.name} copied from {real} so Windows can use it ({changed} file(s))")

    def sync_entry_dirs(self):
        for name in self.manifest.get("perEntryDirs", []):
            shared_dir = self.root / name
            shared_dir.mkdir(parents=True, exist_ok=True)
            local_dir = self.claude / name
            if local_dir.is_symlink():
                continue
            local_dir.mkdir(parents=True, exist_ok=True)
            # Claude-managed per install (claude.ai skill sync); never adopt.
            exclude = set(self.manifest.get("perEntryExclude", []))
            for entry in list(local_dir.iterdir()):
                if entry.name in exclude:
                    continue
                if entry.is_symlink():
                    real = os.path.realpath(entry)
                    if real.startswith("/nix/store/"):
                        self.mirror(real, shared_dir / entry.name)
                    elif not entry.exists() and os.readlink(entry).startswith(str(shared_dir)):
                        entry.unlink()  # deleted on the other OS
                elif entry.is_dir():
                    self.adopt(entry, find_ci(shared_dir, entry.name), f"{name}/{entry.name}")
        self.share_linked_skills()
        self.link_shared_entries()

    def link_shared_entries(self):
        """Link entries added on the other OS (cheap; runs on every launch).
        Not ones that were here before: gone now means uninstalled here,
        which the hook spreads (relinking would undo it)."""
        exclude = set(self.manifest.get("perEntryExclude", []))
        exclude |= self.read_registry()[1].get("skill", set())
        seen = self.read_state().get("seen")
        if isinstance(seen, dict):
            exclude |= set(seen.get("skill", []))
        for name in self.manifest.get("perEntryDirs", []):
            shared_dir = self.root / name
            local_dir = self.claude / name
            if not shared_dir.is_dir() or local_dir.is_symlink():
                continue
            local_dir.mkdir(parents=True, exist_ok=True)
            for entry in shared_dir.iterdir():
                local = local_dir / entry.name
                if entry.name not in exclude and not entry.name.startswith(".") \
                        and not local.exists() and not local.is_symlink():
                    local.symlink_to(entry)

    # ── projects (sessions + auto-memory) ───────────────────────────────
    def shared_project(self, linux_path):
        wpath = self.to_windows(linux_path)
        if wpath is None:
            return None
        lkey, wkey = encode(linux_path), encode(wpath)
        if len(lkey) > MAX_KEY or len(wkey) > MAX_KEY:
            log(f"path too long to share: {linux_path}")
            return None
        return lkey, find_ci(self.root / "projects", wkey)

    def sync_projects(self):
        local_dir = self.claude / "projects"
        shared_dir = self.root / "projects"
        local_dir.mkdir(parents=True, exist_ok=True)
        shared_dir.mkdir(parents=True, exist_ok=True)
        # Linux sessions created before sharing (or by an unwrapped claude).
        for entry in list(local_dir.iterdir()):
            if entry.is_symlink():
                if not entry.exists() and os.readlink(entry).startswith(str(shared_dir)):
                    entry.unlink()
                continue
            cwd = session_cwd(entry) if entry.is_dir() else None
            pair = self.shared_project(cwd) if cwd else None
            if pair and pair[0] == entry.name:
                self.adopt(entry, pair[1], f"projects/{entry.name}")
        # Sessions that exist only in the shared dir (started on Windows).
        for entry in shared_dir.iterdir():
            cwd = session_cwd(entry) if entry.is_dir() else None
            linux_path = self.from_windows(cwd) if cwd else None
            if linux_path is None:
                continue
            local = local_dir / encode(linux_path)
            if encode(self.to_windows(linux_path)).lower() == entry.name.lower() \
                    and not local.exists() and not local.is_symlink():
                local.symlink_to(entry)

    def prepare(self, cwd):
        if not self.healthy():
            return
        self.link_shared_entries()
        pair = self.shared_project(os.path.realpath(cwd))
        if pair is None:
            return
        lkey, target = pair
        target.mkdir(parents=True, exist_ok=True)
        local = self.claude / "projects" / lkey
        local.parent.mkdir(parents=True, exist_ok=True)
        if local.is_dir() and not local.is_symlink():
            self.adopt(local, target, f"projects/{lkey}")
        else:
            self.link(local, target)

    def hook(self, payload):
        """SessionStart hook. Never prints to stdout (main() prints only os_context()): that becomes session context."""
        self.prepare(payload.get("cwd") or os.getcwd())
        if not self.healthy():
            return
        self.sync_removals()
        self.sync_account_skills()
        self.share_linked_skills()
        self.link_shared_entries()
        self.import_mcp()
        self.purge_trash()
        markets, plugins = self.missing()
        if markets or plugins or any(self.unwanted()):
            if os.environ.get("CLAUDE_SHARED_FOREGROUND") == "1":  # tests
                self.plugins("claude")
                return
            # Installs take minutes; finish in the background, live next session.
            state = self.home / ".local" / "state" / "claude-shared"
            state.mkdir(parents=True, exist_ok=True)
            argv = [sys.executable, sys.argv[0]] + sys.argv[1:sys.argv.index("hook")] + ["plugins"]
            with open(state / "plugins.log", "a", encoding="utf-8") as out:
                subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=out, stderr=out, start_new_session=True)
            log(f"installing/uninstalling in background: {', '.join(list(markets) + plugins) or 'removals'}")
        if self.skill_updater:
            # Checks upstream at most daily per repo; returns at once otherwise.
            state = self.home / ".local" / "state" / "claude-shared"
            state.mkdir(parents=True, exist_ok=True)
            with open(state / "skill-update.out", "a", encoding="utf-8") as out:
                subprocess.Popen([self.skill_updater], stdin=subprocess.DEVNULL, stdout=out, stderr=out, start_new_session=True)

    def sync(self):
        self.merge_settings()
        self.merge_mcp()
        if not self.healthy():
            return
        self.root.mkdir(parents=True, exist_ok=True)
        self.sync_link_dirs()
        self.sync_home_links()
        self.sync_removals()
        self.sync_account_skills()
        self.sync_entry_dirs()
        self.sync_projects()
        self.import_mcp()

    def status(self):
        print(f"shared root : {self.root} ({'ok' if self.healthy() else 'UNAVAILABLE'})")
        locals_ = [self.claude / n for n in self.manifest.get("linkDirs", []) + self.manifest.get("perEntryDirs", []) + ["projects"]]
        locals_ += [self.home / n for n in self.manifest.get("homeLinkDirs", {})]
        for local in locals_:
            name = local.name
            kind = f"-> {os.readlink(local)}" if local.is_symlink() else "local dir (per-entry links)"
            print(f"  {name:13} {kind}")
        projects = self.claude / "projects"
        if projects.is_dir():
            shared = sorted(p.name for p in projects.iterdir() if p.is_symlink())
            print(f"shared projects ({len(shared)}):")
            for name in shared:
                print(f"  {name} -> {os.readlink(projects / name)}")


def os_context():
    """One line telling this session which OS it runs on, so it doesn't try the other one's commands."""
    name = "NixOS" if os.path.exists("/etc/NIXOS") else platform.system()
    return (f"Session OS: {name} (Linux), user {os.environ.get('USER', '?')}. Dual-boot with Windows; "
            "E: is /mnt/E_Drive here. Use Linux/bash commands and paths only; never Windows commands "
            "(powershell, cmd, .ps1, winget, C:\\ paths). Don't re-check the OS.")


def main():
    parser = argparse.ArgumentParser(prog="claude-shared")
    parser.add_argument("--shared", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--map", action="append", default=[], help="MOUNTPOINT=LETTER")
    parser.add_argument("--claude-dir", default="~/.claude")
    parser.add_argument("--home", default="~")
    parser.add_argument("--hook-command", help="command registered as the SessionStart hook")
    parser.add_argument("--skill-updater", help="command that refreshes shared skills from upstream (skill-update.ts)")
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("sync")
    sub.add_parser("status")
    sub.add_parser("hook")
    plug = sub.add_parser("plugins")
    plug.add_argument("--claude", default="claude")
    rem = sub.add_parser("removals")
    rem.add_argument("--confirm", dest="mode", action="store_const", const="confirm")
    rem.add_argument("--restore", dest="mode", action="store_const", const="restore")
    prep = sub.add_parser("prepare")
    prep.add_argument("cwd", nargs="?", default=os.getcwd())
    args = parser.parse_args()

    shared = Shared(args)
    if args.cmd == "hook":
        print(os_context())  # the only hook stdout: it becomes this session's context
    if args.cmd in ("sync", "prepare", "hook", "plugins") and sharing_off(shared.claude):
        return 0  # sandbox: nothing here is shared or recorded
    try:
        if args.cmd == "sync":
            shared.sync()
        elif args.cmd == "prepare":
            shared.prepare(args.cwd)
        elif args.cmd == "hook":
            try:
                payload = json.load(sys.stdin)
            except ValueError:
                payload = {}
            shared.hook(payload if isinstance(payload, dict) else {})
        elif args.cmd == "plugins":
            shared.plugins(args.claude)
        elif args.cmd == "removals":
            shared.removals(args.mode)
        else:
            shared.status()
    except Exception as exc:  # never block claude or a rebuild
        log(f"{args.cmd} failed: {exc}")
        return 0 if args.cmd not in ("status", "removals") else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
