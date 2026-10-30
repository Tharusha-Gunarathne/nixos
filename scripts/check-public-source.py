#!/usr/bin/env python3
"""Check staged content or reachable history without printing private values."""

import argparse
import pathlib
import re
import subprocess
import tomllib


def git(*args):
    return subprocess.check_output(["git", *args])


def local_values():
    path = pathlib.Path(".env.local")
    if not path.exists():
        return []
    config = tomllib.loads(path.read_text())
    values = []

    def visit(node, key=""):
        if isinstance(node, dict):
            for name, value in node.items():
                visit(value, key + "." + name)
        elif isinstance(node, str) and len(node) >= 8:
            if re.search(r"password|token|api_key|auth_key", key):
                values.append(node.encode())

    visit(config)
    for entry in config.get("desktop_entries", {}).values():
        for key in ("name", "genericName", "comment", "icon"):
            value = entry.get(key, "")
            if isinstance(value, str) and len(value) >= 8:
                values.append(value.encode())
    return values


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--history", action="store_true")
    args = parser.parse_args()
    patterns = {
        "credential pattern": re.compile(
            rb"gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|"
            rb"AKIA[A-Z0-9]{16}|nvapi-[A-Za-z0-9_-]{20,}|"
            rb"tskey-[A-Za-z0-9_-]{15,}|-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----"
        ),
        "personal home path": re.compile(
            rb"/home/(?!alice(?:/|\b)|user(?:/|\b)|linux-user(?:/|\b))[A-Za-z0-9][A-Za-z0-9_-]*"
        ),
        "personal email": re.compile(
            rb"[A-Za-z0-9_.+-]+@(?:gmail|hotmail|outlook|yahoo|icloud)\.[A-Za-z]{2,}"
        ),
    }
    secrets = local_values()
    if args.history:
        objects = [line.partition(" ")[::2] for line in
                   git("rev-list", "--objects", "--all").decode().splitlines()]
    else:
        objects = []
        for line in git("ls-files", "--stage", "-z").decode().split("\0"):
            if line:
                metadata, path = line.split("\t", 1)
                objects.append((metadata.split()[1], path))
    process = subprocess.Popen(["git", "cat-file", "--batch"],
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    failed = False
    try:
        for oid, path in objects:
            process.stdin.write((oid + "\n").encode())
            process.stdin.flush()
            header = process.stdout.readline().split()
            data = process.stdout.read(int(header[2]))
            process.stdout.read(1)
            if header[1] not in (b"blob", b"commit", b"tag"):
                continue
            hits = [name for name, pattern in patterns.items() if pattern.search(data)]
            if any(value in data for value in secrets):
                hits.append("private local value")
            if path == ".env.local" or path.startswith((".aws/", ".claude/", "private/", ".private/")):
                hits.append("private file")
            if hits:
                print(f"BLOCKED {path or oid}: {', '.join(hits)}")
                failed = True
    finally:
        process.stdin.close()
        process.wait()
    if failed:
        raise SystemExit(1)
    print("Public-source checks passed")


if __name__ == "__main__":
    main()
