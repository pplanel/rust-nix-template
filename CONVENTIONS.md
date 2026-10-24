# Rust Project Conventions

These conventions keep Rust workspaces predictable, easy to navigate, and safe to change for both
human contributors and coding agents. Where a rule can be enforced by `rustfmt`, `clippy`, or CI,
it is — the tooling is the source of truth, and this document explains the intent.

## 1. Workspace shape

Use a Cargo workspace with one crate per clear responsibility:

```text
project/
├── Cargo.toml          # workspace root: members, shared deps, lints
├── rustfmt.toml
├── clippy.toml
└── crates/
    ├── common/         # shared primitives: typed IDs, small value types
    ├── api_models/     # external request/response contracts
    ├── domain/         # business logic and domain models
    ├── storage/        # persistence: DB access, repository implementations
    ├── server/         # HTTP layer, wiring, binary entry point
    └── test_support/   # shared fixtures and test helpers (dev-dependency only)
```

- Prefer small, focused crates over one monolith, but don't split a crate until it has a real
  boundary to protect. A crate with one file is a sign of premature splitting.
- Crate and module names are `snake_case`.
- Set `edition`, `rust-version`, and `license` once in `[workspace.package]` and inherit them.

## 2. Dependency direction

Dependencies point downward only:

```text
common  →  domain  →  storage  →  server
   ↘  api_models  ↗
```

- Lower crates never depend on higher ones; no cycles.
- `common` and `domain` contain no HTTP, database, or runtime code.
- `domain` defines repository **traits**; `storage` implements them. Business logic depends on the
  trait, never on the concrete database type.
- `api_models` holds wire formats only. Convert to/from domain types at the `server` boundary;
  never pass API structs into domain logic.

## 3. Module and file layout

- `lib.rs` is the crate root and should mostly declare modules and re-export the public API.
- Use the `foo.rs` + `foo/` layout for modules with children. Do not use `mod.rs`.
- Name files after the domain concept they hold: `orders.rs`, `pricing.rs`, `validation.rs`.
- Split a file when it holds more than one concern, not by line count alone.
- Integration tests live in `crates/<name>/tests/`; unit tests live in a `#[cfg(test)] mod tests`
  at the bottom of the file they test.

## 4. Naming

- Types, traits, enum variants: `PascalCase`. Functions, methods, variables: `snake_case`.
  Constants and statics: `SCREAMING_SNAKE_CASE`.
- Generic parameters are single letters (`T`, `E`, `K`, `V`) unless a longer name genuinely
  clarifies (`Repo`, `Clock`).
- Name things by what they mean in the domain: `retry_policy`, `order_total`, `shipping_address`.
- Avoid catch-all names for modules and types: `misc`, `stuff`, `helpers`, `Manager`, `Handler`.
  A `utils` module is acceptable only if it stays small; once it grows, split it by topic.

## 5. Types and domain modeling

- Model identifiers as newtypes, one per entity: `UserId(Uuid)`, `OrderId(Uuid)`. Never share one
  ID type across entities.
- Validate at construction, then trust the type: `Email::parse(&str) -> Result<Email, _>` instead
  of passing `String` and re-validating everywhere.
- Use enums for closed sets of states or kinds instead of strings or booleans.
- Avoid passing `serde_json::Value` or `HashMap<String, String>` through business logic; deserialize
  into a struct at the edge.
- Prefer compile-time guarantees over runtime checks when the cost is reasonable.

## 6. Error handling

- **Libraries** (every crate except binaries): define typed errors with `thiserror`. One error enum
  per crate or per major module, with variants that a caller could act on.
- **Binaries and tests**: `anyhow` is allowed for top-level plumbing (`main`, setup code).
- Add context when an error crosses a crate boundary — wrap with a variant that says what was being
  attempted (`#[error("failed to load order {id}")] LoadOrder { id: OrderId, #[source] source: StorageError }`).
- Never return `String` as an error type.
- No `unwrap()`, `expect()`, or `panic!()` in non-test code. The rare justified exception (a true
  invariant) uses `expect("reason the invariant holds")` with a local `#[allow]` and a comment.
- Don't swallow errors: no `let _ = fallible()` and no `unwrap_or` defaults that hide a bad input.
  If a fallback is intended, log it.

```rust
#[derive(Debug, thiserror::Error)]
pub enum OrderError {
    #[error("order total must be positive, got {0}")]
    InvalidTotal(i64),
    #[error("order {0} not found")]
    NotFound(OrderId),
    #[error("storage failure")]
    Storage(#[from] StorageError),
}
```

## 7. Async and runtime

- The runtime is `tokio`. Only binaries and tests choose runtime flavor (`#[tokio::main]`,
  `#[tokio::test]`); libraries stay runtime-agnostic where practical.
- Keep I/O at the edges (`storage`, `server`); domain logic should be mostly synchronous and pure.
- Never block inside async code. Use `tokio::task::spawn_blocking` for CPU-heavy or blocking work.
- Don't hold a `std::sync::Mutex` guard across `.await`; use `tokio::sync::Mutex` or restructure.
- Prefer structured concurrency (`JoinSet`, `join!`, `select!`) over bare `tokio::spawn`. A detached
  spawn needs a reason and must handle or log its error.
- No global mutable state. Pass shared state explicitly (e.g. an `AppState` in the router).

## 8. Configuration and serialization

- All configuration lives in one typed config struct, loaded once at startup in the binary.
- Read environment variables only in the config module, never in domain or storage code.
- Missing required config (database URL, secrets) is a startup error, not a silent default.
- Derive `Serialize`/`Deserialize` only on types that actually cross a boundary.
- Secrets never appear in `Debug` output or logs: wrap them (e.g. `secrecy::SecretString`) or
  implement `Debug` manually.

## 9. Feature flags

- Cargo features must be **additive**: enabling a feature may add capability but never removes or
  changes existing behavior. Never create mutually exclusive features.
- Name features by capability: `openapi`, `postgres`, `metrics`.
- Use features for optional integrations and heavy optional dependencies, not for runtime behavior
  — that belongs in config.
- Every feature combination that CI cares about must build (`cargo hack --feature-powerset check`
  if the set is small enough).

## 10. Logging and observability

- Use `tracing`, never `println!`/`eprintln!` outside of CLI output.
- Initialize the subscriber once, in the binary.
- Use structured fields, not formatted strings: `info!(order_id = %id, "order created")`.
- Instrument boundary functions with `#[tracing::instrument(skip(...))]`, skipping large or secret
  arguments.

## 11. Visibility and API surface

- Default to private, then `pub(crate)`; use `pub` only for items that other crates need.
- Re-export a crate's intended public API from `lib.rs` so consumers don't reach into internals.
- Public items in library crates get a doc comment stating what they do and when they fail.

## 12. Unsafe code

- `unsafe_code = "forbid"` at the workspace level.
- If a crate truly needs `unsafe`, it overrides the lint locally, isolates the unsafe code in a small
  module, and documents every block with a `// SAFETY:` comment explaining why it is sound.

## 13. Testing

- New behavior and bug fixes come with tests. A bug fix's test must fail without the fix.
- Unit tests for logic, integration tests (`tests/`) for crate-level behavior through the public API.
- Tests are deterministic: no real network, no sleeps for synchronization, no reliance on wall-clock
  time (inject a clock instead).
- Shared fixtures go in `test_support`, which is only ever a `[dev-dependencies]` entry.
- `unwrap()`/`expect()` are fine in tests (`allow-unwrap-in-tests = true` in `clippy.toml`).
- Assert on behavior and outputs, not on internal implementation details.

## 14. Dependencies

- Declare every third-party dependency once in `[workspace.dependencies]`; member crates use
  `dep = { workspace = true }`.
- Prefer well-maintained, widely used crates over hand-rolled equivalents for solved problems
  (UUIDs, time, serialization, HTTP).
- Every new dependency needs a clear reason; avoid adding a crate for a few lines of code.
- Keep the tree clean: CI runs `cargo machete` (unused deps) and `cargo deny` (licenses, advisories,
  duplicates).

## 15. Formatting and lints

Formatting is whatever `cargo fmt` produces on stable, using default rustfmt settings (4 spaces,
100 columns). Nightly-only rustfmt options are not used.

Workspace lints (in root `Cargo.toml`, inherited with `[lints] workspace = true`):

```toml
[workspace.lints.rust]
unsafe_code = "forbid"
rust_2018_idioms = { level = "warn", priority = -1 }
missing_debug_implementations = "warn"

[workspace.lints.clippy]
dbg_macro = "warn"
expect_used = "warn"
panic = "warn"
print_stdout = "warn"
print_stderr = "warn"
todo = "warn"
unimplemented = "warn"
unwrap_used = "warn"
as_conversions = "warn"
wildcard_dependencies = "warn"
```

CI gate, which must pass before merge:

```bash
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace --all-features
```

## 16. Rules for coding agents

1. **Pick the right crate first.** Check section 2 before writing code; never put logic in a layer
   that would require a dependency pointing upward.
2. **Follow existing patterns.** If the codebase already solves a similar problem, mirror it. A new
   pattern needs a one-line justification in the PR or commit message.
3. **Make the smallest useful change.** No unrelated refactors, renames, or formatting churn.
4. **No noise.** No speculative abstractions, dead code, commented-out code, or leftover debug
   output.
5. **Verify before finishing.** Run the CI gate from section 15 for the affected crates, and confirm
   no new dependency points upward.
