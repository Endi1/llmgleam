#!/usr/bin/env python3
"""Prepare and publish llmgleam releases.

This script is intentionally project-specific. It bumps gleam.toml, updates
CHANGELOG.md, runs checks, and publishes with a Hex API key loaded from .env.
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
GLEAM_TOML = ROOT / "gleam.toml"
CHANGELOG = ROOT / "CHANGELOG.md"
README_MD = ROOT / "README.md"
README_ORG = ROOT / "README.org"
PACKAGE = "llmgleam"
SEMVER_RE = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
VERSION_LINE_RE = re.compile(r'(?m)^version = "([^"]+)"\s*$')


class ReleaseError(Exception):
    pass


def run(cmd: list[str], *, input_text: str | None = None, env: dict[str, str] | None = None) -> None:
    printable = " ".join(cmd)
    print(f"$ {printable}")
    subprocess.run(
        cmd,
        cwd=ROOT,
        input=input_text,
        text=True,
        env=env,
        check=True,
    )


def capture(cmd: list[str]) -> str:
    return subprocess.check_output(cmd, cwd=ROOT, text=True).strip()


def parse_version(version: str) -> tuple[int, int, int]:
    match = SEMVER_RE.match(version)
    if not match:
        raise ReleaseError(f"Invalid semantic version: {version!r}")
    return tuple(int(part) for part in match.groups())  # type: ignore[return-value]


def bump_version(current: str, bump: str) -> str:
    major, minor, patch = parse_version(current)
    if bump == "patch":
        patch += 1
    elif bump == "minor":
        minor += 1
        patch = 0
    elif bump == "major":
        major += 1
        minor = 0
        patch = 0
    else:
        raise ReleaseError(f"Unknown bump type: {bump}")
    return f"{major}.{minor}.{patch}"


def current_version() -> str:
    text = GLEAM_TOML.read_text()
    match = VERSION_LINE_RE.search(text)
    if not match:
        raise ReleaseError("Could not find version line in gleam.toml")
    return match.group(1)


def replace_current_version(new_version: str) -> str:
    old_version = current_version()
    parse_version(new_version)
    if new_version == old_version:
        raise ReleaseError(f"New version is the same as current version: {new_version}")
    text = GLEAM_TOML.read_text()
    updated, count = VERSION_LINE_RE.subn(f'version = "{new_version}"', text, count=1)
    if count != 1:
        raise ReleaseError("Expected exactly one version line in gleam.toml")
    GLEAM_TOML.write_text(updated)
    return old_version


def normalize_notes(notes: str, version: str) -> str:
    notes = notes.strip()
    if not notes:
        notes = f"### Changed\n- Released version {version}."
    # If caller gave plain bullets/text, put it under Changed.
    if not re.search(r"(?m)^###\s+", notes):
        lines = [line.rstrip() for line in notes.splitlines() if line.strip()]
        bullet_lines = []
        for line in lines:
            bullet_lines.append(line if line.startswith("-") else f"- {line}")
        notes = "### Changed\n" + "\n".join(bullet_lines)
    return notes.rstrip() + "\n"


def read_notes(args: argparse.Namespace, version: str) -> str:
    parts: list[str] = []
    if args.notes:
        parts.append(args.notes)
    if args.notes_file:
        parts.append(Path(args.notes_file).read_text())
    if not parts:
        return ""
    return normalize_notes("\n\n".join(parts), version)


def update_changelog(old_version: str, new_version: str, notes: str) -> None:
    text = CHANGELOG.read_text()
    if f"## [{new_version}]" in text:
        raise ReleaseError(f"CHANGELOG.md already has a section for {new_version}")

    today = dt.date.today().isoformat()
    heading_re = re.compile(r"(?ms)^## \[Unreleased\]\s*(.*?)(?=^## \[|^\[Unreleased\]:)")
    match = heading_re.search(text)
    if not match:
        raise ReleaseError("Could not find ## [Unreleased] section in CHANGELOG.md")

    unreleased_body = match.group(1).strip()
    release_notes = notes.strip() if notes.strip() else unreleased_body
    release_notes = normalize_notes(release_notes, new_version).rstrip()

    replacement = f"## [Unreleased]\n\n## [{new_version}] — {today}\n\n{release_notes}\n\n"
    text = text[: match.start()] + replacement + text[match.end() :]

    unreleased_link_re = re.compile(rf"(?m)^\[Unreleased\]: .*$")
    new_unreleased_link = f"[Unreleased]: https://github.com/Endi1/llmgleam/compare/v{new_version}...HEAD"
    text, count = unreleased_link_re.subn(new_unreleased_link, text, count=1)
    if count != 1:
        raise ReleaseError("Could not update [Unreleased] link in CHANGELOG.md")

    new_release_link = f"[{new_version}]: https://github.com/Endi1/llmgleam/compare/v{old_version}...v{new_version}"
    lines = text.splitlines()
    try:
        idx = next(i for i, line in enumerate(lines) if line.startswith(f"[{old_version}]: "))
    except StopIteration as error:
        raise ReleaseError(f"Could not find changelog link for previous version {old_version}") from error
    lines.insert(idx, new_release_link)
    CHANGELOG.write_text("\n".join(lines) + "\n")


def ensure_readme() -> None:
    if README_MD.exists() and README_MD.read_text().strip():
        return
    if README_ORG.exists() and shutil.which("pandoc"):
        run(["pandoc", "-f", "org", "-t", "gfm", "README.org", "-o", "README.md"])
        return
    raise ReleaseError("README.md is required for publishing. Create it before publishing.")


def gleam_cmd() -> list[str]:
    if shutil.which("mise"):
        return ["mise", "exec", "gleam@1.17.0", "--", "gleam"]
    return ["gleam"]


def parse_dotenv(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not key or key.startswith("export "):
            key = key.removeprefix("export ").strip()
        if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
            value = value[1:-1]
        values[key] = value
    return values


def publish_env() -> dict[str, str]:
    env = os.environ.copy()
    if not env.get("HEXPM_API_KEY"):
        env.update({k: v for k, v in parse_dotenv(ROOT / ".env").items() if k == "HEXPM_API_KEY"})
    if not env.get("HEXPM_API_KEY"):
        raise ReleaseError("HEXPM_API_KEY is not set and was not found in .env")
    return env


def ensure_not_already_published(version: str) -> None:
    url = f"https://hex.pm/api/packages/{PACKAGE}/releases/{version}"
    request = urllib.request.Request(url, headers={"accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            if response.status == 200:
                raise ReleaseError(f"{PACKAGE} {version} is already published on Hex")
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return
        raise ReleaseError(f"Could not check Hex release status: HTTP {error.code}") from error


def run_checks() -> None:
    cmd = gleam_cmd()
    run([*cmd, "--version"])
    run([*cmd, "format", "--check"])
    run([*cmd, "test"])


def publish(version: str, *, yes: bool) -> None:
    if not yes:
        raise ReleaseError("Publishing requires --yes")
    ensure_readme()
    ensure_not_already_published(version)
    env = publish_env()
    major, _, _ = parse_version(version)
    publish_input = "I am not using semantic versioning\n" if major == 0 else ""
    run([*gleam_cmd(), "publish", "-y"], input_text=publish_input, env=env)


def print_summary(old_version: str | None, new_version: str) -> None:
    if old_version:
        print(f"Prepared {PACKAGE} release: {old_version} -> {new_version}")
    else:
        print(f"Publishing {PACKAGE} release: {new_version}")
    print("Review changes with: git diff -- gleam.toml CHANGELOG.md README.md")


def main() -> int:
    parser = argparse.ArgumentParser(description="Prepare and publish llmgleam releases")
    version_group = parser.add_mutually_exclusive_group()
    version_group.add_argument("--bump", choices=["patch", "minor", "major"], help="Version bump to apply")
    version_group.add_argument("--version", help="Exact version to set")
    parser.add_argument("--notes", help="Changelog notes as Markdown")
    parser.add_argument("--notes-file", help="Path to changelog notes Markdown")
    parser.add_argument("--publish", action="store_true", help="Publish after optional preparation")
    parser.add_argument("--no-publish", action="store_true", help="Prepare only; do not publish")
    parser.add_argument("--yes", action="store_true", help="Confirm publishing")
    args = parser.parse_args()

    if args.publish and args.no_publish:
        raise ReleaseError("Use only one of --publish or --no-publish")
    if not (args.bump or args.version or args.publish):
        raise ReleaseError("Specify --bump/--version to prepare, or --publish to publish current version")

    old_version: str | None = None
    if args.bump or args.version:
        old = current_version()
        new = args.version or bump_version(old, args.bump)
        notes = read_notes(args, new)
        old_version = replace_current_version(new)
        update_changelog(old_version, new, notes)
        ensure_readme()
        version = new
    else:
        version = current_version()

    print_summary(old_version, version)
    run_checks()

    if args.publish:
        publish(version, yes=args.yes)
        print(f"Published {PACKAGE} v{version}")
    else:
        print("Prepared release but did not publish. Run with --publish --yes after reviewing the diff.")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as error:
        print(f"Command failed with exit code {error.returncode}", file=sys.stderr)
        raise SystemExit(error.returncode)
    except ReleaseError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
