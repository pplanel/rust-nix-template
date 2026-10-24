#![allow(clippy::unwrap_used)]

use axum::{body::Body, http::Request, http::StatusCode};
use tower::ServiceExt;

#[tokio::test]
async fn health_returns_ok() {
    let response = server::app()
        .oneshot(Request::get("/health").body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
}
