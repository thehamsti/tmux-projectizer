#!/usr/bin/env bash
set -euo pipefail

# release.sh — bump version, tag, push, and create a GitHub Release
#
# Usage:
#   ./scripts/release.sh patch    # 1.0.0 -> 1.0.1
#   ./scripts/release.sh minor    # 1.0.0 -> 1.1.0
#   ./scripts/release.sh major    # 1.0.0 -> 2.0.0
#   ./scripts/release.sh 1.2.3    # explicit version

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$ROOT_DIR/tmux-projectizer.tmux"
CHANGELOG_FILE="$ROOT_DIR/CHANGELOG.md"

# ── helpers ──────────────────────────────────────────────

red()   { printf '\033[31m%s\033[0m\n' "$1"; }
green() { printf '\033[32m%s\033[0m\n' "$1"; }
yellow() { printf '\033[33m%s\033[0m\n' "$1"; }
bold()  { printf '\033[1m%s\033[0m\n' "$1"; }

die() {
  red "ERROR: $1"
  exit 1
}

info() {
  bold "$1"
}

# ── read current version ─────────────────────────────────

read_current_version() {
  grep -o 'PROJECTIZER_VERSION="[^"]*"' "$VERSION_FILE" \
    | head -1 \
    | sed 's/PROJECTIZER_VERSION="//; s/"//'
}

# ── bump version ─────────────────────────────────────────

bump_version() {
  local current="$1"
  local part="$2"

  IFS='.' read -r major minor patch <<< "$current"

  case "$part" in
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      ;;
    patch)
      patch=$((patch + 1))
      ;;
    *)
      die "Unknown bump part: $part (use major, minor, or patch)"
      ;;
  esac

  printf '%d.%d.%d' "$major" "$minor" "$patch"
}

# ── validate version string ──────────────────────────────

validate_version() {
  local version="$1"
  if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    die "Invalid version format: $version (expected MAJOR.MINOR.PATCH)"
  fi
}

# ── generate changelog from git log ──────────────────────

generate_changelog() {
  local new_version="$1"
  local previous_tag="${2:-}"
  local range

  if [[ -n "$previous_tag" ]]; then
    range="${previous_tag}..HEAD"
  else
    range="HEAD"
  fi

  local log
  log="$(git -C "$ROOT_DIR" log "$range" --pretty=format:"- %s (%h)" --no-decorate 2>/dev/null || true)"

  if [[ -z "$log" ]]; then
    log="- No commits found in range"
  fi

  printf '## v%s\n\n%s\n\n' "$new_version" "$log"
}

# ── update CHANGELOG.md ──────────────────────────────────

update_changelog_file() {
  local entry="$1"
  local tmp

  tmp="$(mktemp)"

  {
    printf '# Changelog\n\n'
    if [[ -f "$CHANGELOG_FILE" ]]; then
      # Skip the existing header if present
      sed '/^# Changelog$/d; /^$/d' "$CHANGELOG_FILE" 2>/dev/null || true
      printf '\n'
    fi
    printf '%s' "$entry"
  } > "$tmp"

  mv "$tmp" "$CHANGELOG_FILE"
}

# ── main ─────────────────────────────────────────────────

main() {
  local bump_type="${1:-}"
  local current_version
  local new_version
  local previous_tag

  current_version="$(read_current_version)"
  info "Current version: $current_version"

  # Determine new version
  if [[ -z "$bump_type" ]]; then
    die "Usage: $0 <major|minor|patch|VERSION>"
  fi

  if [[ "$bump_type" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    new_version="$bump_type"
  else
    new_version="$(bump_version "$current_version" "$bump_type")"
  fi

  validate_version "$new_version"

  if [[ "$new_version" == "$current_version" ]]; then
    die "New version is the same as current version ($current_version)"
  fi

  info "New version:     $new_version"
  echo ""

  # Find the most recent existing tag for changelog range
  previous_tag="$(git -C "$ROOT_DIR" describe --tags --abbrev=0 2>/dev/null || true)"

  # Generate changelog
  local changelog_entry
  changelog_entry="$(generate_changelog "$new_version" "$previous_tag")"

  printf '%s' "$changelog_entry"
  echo ""

  # ── preflight checks ───────────────────────────────────

  if ! command -v gh &>/dev/null; then
    die "gh CLI is required. Install it from https://cli.github.com"
  fi

  local branch
  branch="$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD)"
  if [[ "$branch" != "main" && "$branch" != "master" ]]; then
    yellow "WARNING: You are on branch '$branch', not main/master."
    read -rp "Continue anyway? [y/N] " confirm
    [[ "${confirm:-}" =~ ^[Yy]$ ]] || die "Aborted."
  fi

  if ! git -C "$ROOT_DIR" diff --quiet 2>/dev/null; then
    die "Working tree has uncommitted changes. Commit or stash first."
  fi

  # ── confirm ────────────────────────────────────────────

  read -rp "Release v${new_version}? [y/N] " confirm
  [[ "${confirm:-}" =~ ^[Yy]$ ]] || die "Aborted."

  # ── update version in source ───────────────────────────

  sed -i '' "s/PROJECTIZER_VERSION=\"${current_version}\"/PROJECTIZER_VERSION=\"${new_version}\"/" "$VERSION_FILE"

  info "Updated PROJECTIZER_VERSION in $(basename "$VERSION_FILE")"

  # ── update CHANGELOG.md ────────────────────────────────

  update_changelog_file "$changelog_entry"
  info "Updated CHANGELOG.md"

  # ── commit ─────────────────────────────────────────────

  git -C "$ROOT_DIR" add "$VERSION_FILE" "$CHANGELOG_FILE"
  git -C "$ROOT_DIR" commit -m "release: v${new_version}"
  info "Committed version bump"

  # ── tag ────────────────────────────────────────────────

  local tag="v${new_version}"
  git -C "$ROOT_DIR" tag -a "$tag" -m "Release ${tag}"
  info "Created annotated tag: $tag"

  # ── push ───────────────────────────────────────────────

  git -C "$ROOT_DIR" push origin "$branch"
  git -C "$ROOT_DIR" push origin "$tag"
  info "Pushed commit and tag to origin"

  # ── GitHub Release ─────────────────────────────────────

  local release_notes
  release_notes="$(generate_changelog "$new_version" "$previous_tag")"

  gh release create "$tag" \
    --repo thehamsti/tmux-projectizer \
    --title "Release ${tag}" \
    --notes "$release_notes"

  green ""
  green "=== Release v${new_version} published! ==="
  green ""
  green "  https://github.com/thehamsti/tmux-projectizer/releases/tag/${tag}"
  echo ""
}

main "$@"
