---
name: publish-llmgleam
description: Release workflow for this llmgleam package. Use when asked to publish a new Hex version: bump gleam.toml, update CHANGELOG.md, run checks, load HEXPM_API_KEY from .env, and publish with Gleam.
---

# Publish llmgleam

Use this skill when publishing a new version of the `llmgleam` Gleam package to Hex.

The release must do these things in order:

1. Bump the version in `gleam.toml`.
2. Update `CHANGELOG.md`.
3. Run checks.
4. Publish to Hex using `HEXPM_API_KEY` from `.env`.

## Safety rules

- Do not print or reveal `.env` contents or the Hex API key.
- Use Gleam >= 1.17 for publishing. Gleam 1.14 can fail with a Hex `400 Bad Request`.
- Do not publish without explicit user intent for the release version and changelog notes.
- Before publishing, show the user the planned version and the diff for `gleam.toml` and `CHANGELOG.md`.
- Do not include unrelated local files in the release commit. In this repo, `notes.org` is local scratch and should be ignored unless the user says otherwise.
- `README.md` must exist for newer Gleam publish commands.

## Recommended workflow

From the repository root:

1. Inspect current state:

```bash
git status --short
grep -E '^version = ' gleam.toml
```

2. Ask the user for:
   - release bump: `patch`, `minor`, `major`, or an exact version like `0.0.8`
   - changelog notes, grouped if possible under `Added`, `Changed`, `Fixed`, etc.

3. Prepare the release without publishing:

```bash
.pi/skills/publish-llmgleam/scripts/publish_release.py --bump patch --notes-file /tmp/llmgleam-release-notes.md --no-publish
```

or for an exact version:

```bash
.pi/skills/publish-llmgleam/scripts/publish_release.py --version 0.0.8 --notes-file /tmp/llmgleam-release-notes.md --no-publish
```

If the user has no detailed notes, use `--notes "Released version X."` or first summarize the git diff since the last tag.

4. Review and show the diff:

```bash
git diff -- gleam.toml CHANGELOG.md README.md
```

5. Publish only after confirmation:

```bash
.pi/skills/publish-llmgleam/scripts/publish_release.py --publish --yes
```

The script loads `HEXPM_API_KEY` from `.env` if it is not already present in the environment. It does not print the key.

6. Verify publication:

```bash
python3 - <<'PY'
import json, urllib.request
pkg = json.load(urllib.request.urlopen('https://hex.pm/api/packages/llmgleam', timeout=20))
print(pkg['latest_version'])
PY
```

7. Suggest post-publish git steps:

```bash
git add gleam.toml CHANGELOG.md README.md .pi/skills/publish-llmgleam
git commit -m "chore: release vX.Y.Z"
git tag vX.Y.Z
git push origin main --tags
```

Only run git commit/tag/push if the user asks.

## One-command workflow

If the user explicitly asks to bump and publish immediately, this is acceptable after confirming the exact version and notes:

```bash
.pi/skills/publish-llmgleam/scripts/publish_release.py --bump patch --notes-file /tmp/llmgleam-release-notes.md --publish --yes
```
