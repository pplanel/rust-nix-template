set shell := ["bash", "-euo", "pipefail", "-c"]

# List available recipes.
default:
    @just --list

# ---------------------------------------------------------------------------
# Inner loop: fast local Cargo (no Nix sandbox rebuild per edit)
# ---------------------------------------------------------------------------

# Full local gate: format check, clippy, tests, and a stale-hakari check.
check: fmt-check clippy test hakari-verify

# Format every crate in place.
fmt:
    cargo fmt --all

# Fail if anything is unformatted (CI-style).
fmt-check:
    cargo fmt --all -- --check

# Clippy across the whole workspace; warnings are errors.
clippy:
    cargo clippy --workspace --all-targets --all-features -- -D warnings

# Run the test suite with nextest.
test:
    cargo nextest run --workspace --all-features

# Rebuild and re-check on every change.
watch:
    cargo watch -x "clippy --workspace --all-targets" -x "nextest run --workspace"

# ---------------------------------------------------------------------------
# Hermetic verification: full Nix sandbox (slower, what CI mirrors)
# ---------------------------------------------------------------------------

# Run the complete flake check (clippy, fmt, nextest, build) hermetically.
check-nix:
    nix flake check

# Build the default package through Nix.
build-nix:
    nix build

# ---------------------------------------------------------------------------
# Workspace bootstrapping (cargo-hakari / workspace-hack)
# ---------------------------------------------------------------------------

# Wire the workspace-hack into every crate and regenerate it (run after adding a crate/dep).
bootstrap:
    cargo hakari manage-deps
    cargo hakari generate

# Fail if the workspace-hack is stale (run `just bootstrap` to fix).
hakari-verify:
    cargo hakari generate --diff
    cargo hakari verify

# ---------------------------------------------------------------------------
# Release (cocogitto bumps versions/tags, git-cliff writes the changelog)
# Requires cog.toml and cliff.toml, which this boilerplate does not ship yet.
# ---------------------------------------------------------------------------

# Preview the next conventional-commit bump and the unreleased changelog.
release-dry:
    cog bump --dry-run --auto
    git cliff --unreleased

# Cut a release: auto-bump versions and tags from conventional commits.
release:
    cog bump --auto

# Bump to an explicit version, e.g. `just release-version 1.2.0`.
release-version version:
    cog bump {{ version }}

# Regenerate CHANGELOG.md from the full git history.
changelog:
    git cliff -o CHANGELOG.md

# Bootstrap workspace identifiers, hooks, hakari, and v0.1.0 tag
init project_name="my-cli" github_owner="my-org":
    sd "my-org/my-repo" "{{ github_owner }}/{{ project_name }}" Cargo.toml cliff.toml flake.nix; \
    sd "my-org" "{{ github_owner }}" flake.nix; \
    sd "my-cli" "{{ project_name }}" Cargo.toml flake.nix .github/workflows/ci.yml; \
    rm -f cargo-generate.toml post-generate.rhai
    cargo hakari generate
    cargo hakari manage-deps
    cargo generate-lockfile
    @if ! git rev-parse v0.1.0 >/dev/null 2>&1; then \
        git init && \
        git add -A && \
        git commit -m "chore: initial workspace skeleton" && \
        git tag -a v0.1.0 -m "Initial release baseline"; \
    fi
    cog install-hook --all
