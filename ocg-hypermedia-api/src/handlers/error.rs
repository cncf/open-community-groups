//! This module defines a `HandlerError` type to improve error handling in
//! handlers.

use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
};
use tracing::error;

/// Wrapper around `anyhow::Error` to improve error handling in handlers.
pub(crate) struct HandlerError(anyhow::Error);

/// Allows to convert a `HandlerError` into a `Response`.
impl IntoResponse for HandlerError {
    fn into_response(self) -> Response {
        error!("{:?}", self.0);
        StatusCode::INTERNAL_SERVER_ERROR.into_response()
    }
}

/// Allows to convert an `anyhow::Error` into a `HandlerError`.
impl<E> From<E> for HandlerError
where
    E: Into<anyhow::Error>,
{
    fn from(err: E) -> Self {
        Self(err.into())
    }
}
