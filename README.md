# rust-boilerplate

A starter Cargo workspace for new Rust services, built to work cleanly with Nix and `direnv`.

This repository is intentionally minimal: it gives you a workspace layout, shared dependency setup, linting, and a verified local workflow without locking you into a specific app domain.

## What is included

- Cargo workspace with layered crates:
  - `crates/common` — shared primitives and typed values
  - `crates/domain` — business logic and repository traits
  - `crates/server` — HTTP layer and binary entry point
  - `crates/my-workspace-hack` — generated workspace-hack crate for `cargo-hakari`
- Nix flake for reproducible Rust toolchains and dev tooling
- `direnv` integration via `.envrc`
- `just` workflows for local checks and hermetic verification
- Standard workspace linting and formatting configuration

## Repository layout

```text
.
├── .envrc
├── .github/
├── Cargo.toml
├── Cargo.lock
├── Justfile
├── flake.nix
├── rustfmt.toml
├── clippy.toml
├── CHANGELOG.md
├── CONVENTIONS.md
├── crates/
│   ├── common/
│   ├── domain/
│   ├── server/
│   └── my-workspace-hack/
├── .gitignore
├── cliff.toml
├── cog.toml
├── cargo-generate.toml
├── post-generate.rhai
└── README.md
```

## Prerequisites

For the default local workflow, you can either:

- use the repo's Nix environment via `direnv`, or
- install the Rust toolchain locally and use Cargo directly.

The repository expects the Nix flake to provide the pinned toolchain and helpers such as:

- `cargo-nextest`
- `cargo-hakari`
- `cargo-release`
- `cargo-edit`
- `cargo-watch`
- `git-cliff`
- `cocogitto`
- `just`

## Quick start

```bash
# Load the flake-managed dev environment
cd rust-nix-template
direnv allow

# Fast local quality gate
just check
```

If you are starting from a clean checkout and want the full hermetic verification path:

```bash
just check-nix
```

## Useful commands

This project uses `just` as the main entry point:

```bash
just --list
just fmt
just fmt-check
just clippy
just test
just check
just check-nix
just build-nix
just bootstrap
just hakari-verify
```

## Project conventions

The repo follows the rules in `CONVENTIONS.md`, which is the source of truth for:

- workspace structure
- dependency direction
- naming and module layout
- error handling
- testing expectations
- lint and formatting requirements
- safety rules (`unsafe_code = "forbid"`)

Important notes from the conventions:

- Dependencies point downward only: `common -> domain -> server`
- Add new crates only when there is a real boundary
- Use `thiserror` in libraries; `anyhow` is okay in binaries/tests
- Prefer typed domain models and validated constructors
- Write tests alongside every behavior change
- Do not edit `crates/my-workspace-hack` by hand

## CI expectations

The workspace is intended to satisfy the standard Rust checks:

```bash
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace --all-features
cargo hakari generate --diff && cargo hakari verify
```

## Why this template exists

This project is designed as a lightweight starting point for new Rust services. It keeps the project structure simple, reduces accidental architecture drift, and makes the Nix + Cargo workflow easy to repeat across new services.

## License

This project is licensed under the Apache 2.0 License.
