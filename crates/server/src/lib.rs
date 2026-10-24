//! HTTP layer and wiring.

use axum::{Router, routing::get};

/// Builds the application router.
pub fn app() -> Router {
    Router::new().route("/health", get(|| async { "ok" }))
}
