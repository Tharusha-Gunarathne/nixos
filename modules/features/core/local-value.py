"""Read one optional string from a local TOML file at runtime."""

import pathlib
import sys
import tomllib


def main():
    path, section, key = sys.argv[1:]
    try:
        with pathlib.Path(path).open("rb") as handle:
            value = tomllib.load(handle).get(section, {}).get(key, "")
    except FileNotFoundError:
        value = ""
    if not isinstance(value, str) or "\n" in value or "\r" in value or "\0" in value:
        raise SystemExit("Local setting must be a single-line string")
    sys.stdout.write(value)


if __name__ == "__main__":
    main()
