# rust-boilerplate

A starter Cargo workspace (Rust edition 2024) for new services. **`CONVENTIONS.md`
is the authoritative spec** for how code here is structured, named, tested, and
reviewed. Read it before writing or changing code; this file only orients you and
records what's actually present.

## Current layout

```text
crates/
├── common/   # shared primitives (typed IDs, value types); no I/O, no runtime
├── domain/   # business logic + repository traits; no HTTP/DB; depends on common
└── server/   # axum HTTP layer + binary entry point; depends on domain
```

Dependencies point downward only: `common → domain → server`. Never introduce a
dependency that points upward or creates a cycle (CONVENTIONS §2).

The convention's full target shape also names `api_models`, `storage`, and
`test_support` crates — add them when a real boundary appears, not before
(CONVENTIONS §1). The boilerplate starts minimal on purpose.

## Commands

The CI gate that must pass before merge (CONVENTIONS §15):

```bash
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace --all-features
```

Run it; all three are currently green. Default rustfmt (4 spaces, 100 cols) — no
`rustfmt.toml`, no nightly-only options. Lints live in the root `Cargo.toml`
`[workspace.lints]` and are inherited per crate with `[lints] workspace = true`.

## What agents must keep in mind

- **Pick the right crate first** — never put logic in a layer that would force an
  upward dependency.
- **Typed errors with `thiserror`** in libraries; `anyhow` only in binaries/tests.
  No `unwrap`/`expect`/`panic!` in non-test code; no `String` errors; don't swallow
  errors (CONVENTIONS §6).
- **New dependencies** go in `[workspace.dependencies]` once, used as
  `dep = { workspace = true }`, and each needs a clear reason (CONVENTIONS §14).
- **Tests come with every change**; a bug-fix test must fail without the fix.
  Unit tests inline in `#[cfg(test)] mod tests`, integration tests in
  `crates/<name>/tests/` (CONVENTIONS §13).
- `unsafe_code = "forbid"` workspace-wide (CONVENTIONS §12).
- Use `foo.rs` + `foo/`, never `mod.rs`. `lib.rs` declares modules and re-exports
  the public API (CONVENTIONS §3).
- Smallest useful change, no speculative abstractions or unrelated churn, verify
  the CI gate before finishing (CONVENTIONS §16).
