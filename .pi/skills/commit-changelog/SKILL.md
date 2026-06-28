---
name: commit-changelog
description: Commit staged or dirty changes with a conventional commit message and update CHANGELOG.md under [Unreleased]. Use when the user says "commit", "commit and update changelog", or similar.
---

# Commit & Changelog

This skill covers committing code changes and keeping `CHANGELOG.md` up to date. The changelog follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) with `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, and `Security` sections under `[Unreleased]`.

## Workflow

### 1. Inspect what changed

```bash
git status --short
git diff --stat
```

If there are only staged changes, work with those. If there are unstaged changes, ask the user whether to stage everything (`git add …`) or only specific files.

Also check whether a `CHANGELOG.md` exists:

```bash
cat CHANGELOG.md 2>/dev/null || echo "NO CHANGELOG"
```

### 2. Determine the change category

Read the diff to understand what changed, then map it to a Keep a Changelog section:

| Change type | Section |
|---|---|
| New features or functionality | `Added` |
| Behavior changes, API tweaks | `Changed` |
| Bug fixes | `Fixed` |
| Removed features | `Removed` |
| Deprecations | `Deprecated` |
| Security fixes | `Security` |

### 3. Write the changelog entry

Describe what changed from the user's perspective. Keep it concise (one line per entry). Group related changes under the same bullet.

If `CHANGELOG.md` does not exist, create it with the Keep a Changelog skeleton plus the new entry.

### 4. Update CHANGELOG.md

Insert the entry under `## [Unreleased]`. For a new section, add the `### <Section>` heading followed by the bullet(s). Keep existing entries intact.

Example edit:

```markdown
## [Unreleased]

### Fixed
- GPT `chat_message_decoder` no longer crashes the BEAM process on unrecognized roles

## [0.0.7] — 2026-06-28
```

If the section already exists, append the new bullet to it instead of creating a duplicate heading.

### 5. Commit

Use a [conventional commit](https://www.conventionalcommits.org/) message:

```
<type>: <short description>

<optional body with details>
```

Types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `style`, `ci`, `perf`.

Stage the changed source files plus `CHANGELOG.md`. Do not stage unrelated local files (e.g. `notes.org`, `.env`, scratch files) unless the user explicitly asks.

```bash
git add <source files> CHANGELOG.md
git commit -m "<type>: <description>"
```

### 6. Show the result

```bash
git log --oneline -1
git show --stat HEAD
```

## Notes

- If the user is on a feature branch, keep the commit there; do not merge or push without asking.
- If `[Unreleased]` already has entries, add the new one after existing entries in the same section, or create a new section if the category differs.
- Avoid shell-interpreted characters (backticks, `$`, `!`) in commit messages by using single-quoted strings or a temp file.
