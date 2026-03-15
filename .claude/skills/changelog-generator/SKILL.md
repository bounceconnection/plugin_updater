---
name: changelog-generator
description: >
  Generate and maintain a CHANGELOG.md for Pluginventory from git history using Keep a Changelog
  format. Use whenever the user asks to: generate or update a changelog, write release notes,
  prepare for a release, summarize what changed between versions or since a tag, document what
  shipped, determine version bump (patch/minor/major), or create a CHANGELOG.md from scratch.
  Trigger on phrases like "what changed", "release notes", "what version should this be",
  "prepare the changelog", "summarize recent commits for users", "what went out this week".
  Do NOT trigger for: git log viewing, PR diff summaries, code review, commit message writing,
  or CI/CD workflow setup — those are different tasks.
---

# Changelog Generator for Pluginventory

This skill generates and maintains a CHANGELOG.md following the
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format, combined with
[Semantic Versioning](https://semver.org/).

## Format

The changelog uses this structure:

```markdown
# Changelog

All notable changes to Pluginventory are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- New features

### Changed
- Changes to existing functionality

### Fixed
- Bug fixes

### Removed
- Removed features

## [1.2.0] - 2024-03-14

### Added
- ...
```

## Change Categories

Use exactly these categories (omit empty ones):

| Category    | When to use |
|-------------|------------|
| **Added**   | New features, new files, new capabilities |
| **Changed** | Modifications to existing behavior, refactors that affect users |
| **Fixed**   | Bug fixes |
| **Removed** | Removed features or deprecated items |
| **Security** | Vulnerability fixes |

## How to Generate

### Step 1: Find version boundaries

```bash
cd ~/pluginventory
git tag --sort=-v:refname | head -10      # List recent tags
git log --oneline v1.0.0..HEAD            # Changes since last tag
git log --oneline v0.9.0..v1.0.0          # Changes between two tags
```

### Step 2: Categorize commits

Read each commit message and the diff if the message is unclear. Classify into
the categories above. Group related commits into a single changelog entry when
they're part of the same feature.

Guidelines for writing entries:
- **Start with a verb**: "Add", "Fix", "Update", "Remove", "Improve"
- **Be user-facing**: Describe what changed from the user's perspective, not internal refactors
- **Be specific**: "Add CPU architecture detection with legacy plugin warnings" not "Update scanner"
- **One line per change**: Keep entries concise but informative
- **Skip internal-only changes**: Build system tweaks, code style changes, and test-only
  changes don't need changelog entries unless they affect the user experience

### Step 3: Determine version bump

Follow semver based on the changes:
- **Patch** (0.0.x): Bug fixes, minor improvements that don't change behavior
- **Minor** (0.x.0): New features, non-breaking changes
- **Major** (x.0.0): Breaking changes (rare for a desktop app)

### Step 4: Write or update CHANGELOG.md

The changelog lives at `~/pluginventory/CHANGELOG.md` (repo root).

When updating:
- Add the new version section below `[Unreleased]`
- Move unreleased items into the new version
- Add the date in ISO format (YYYY-MM-DD)
- Keep the `[Unreleased]` section for future changes

## Commit Message Patterns in This Repo

The repo uses descriptive commit messages (not strict Conventional Commits). Examples:

```
Add background image prefetching, in-flight dedup, and BrandLogo asset
Switch license from GPL-3.0 to MIT
Fix release build: generate AppVersion.swift before xcodegen
Add git-based version generation, column auto-resize, and release workflow improvements
```

When parsing these:
- "Add ..." → **Added**
- "Fix ..." → **Fixed**
- "Switch/Change/Update ..." → **Changed**
- "Remove/Delete ..." → **Removed**
- Multi-part commits (comma-separated) may span multiple categories

## Release Workflow Integration

This project uses GitHub Actions for releases:
- Releases are tagged as `vX.Y.Z`
- The "Promote to Main" workflow auto-increments versions
- After generating the changelog, the version tag should match the changelog header
