//! This module defines a `HandlerError` type to make error propagation easier
//! in handlers.

use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
};

use crate::templates::community::explore::FilterError;

/// Represents all possible errors that can occur in a handler.
#[derive(thiserror::Error, Debug)]
pub(crate) enum HandlerError {
    /// Error related to authentication, contains a message.
    #[error("authentication error")]
    Auth(String),

    /// Any other error, wrapped in `anyhow::Error` for flexibility.
    #[error(transparent)]
    Other(#[from] anyhow::Error),

    /// Error during JSON serialization or deserialization.
    #[error("serde json error: {0}")]
    Serde(#[from] serde_json::Error),

    /// Error related to session management.
    #[error("session error: {0}")]
    Session(#[from] tower_sessions::session::Error),

    /// Error during template rendering.
    #[error("template error: {0}")]
    Template(#[from] askama::Error),

    /// Validation error, contains the validation report.
    #[error("validation error: {0}")]
    Validation(#[from] garde::Report),
}

/// Enables conversion of `HandlerError` into an HTTP response for Axum handlers.
impl IntoResponse for HandlerError {
    fn into_response(self) -> Response {
        match self {
            HandlerError::Auth(_) => StatusCode::UNAUTHORIZED.into_response(),
            HandlerError::Validation(report) => {
                (StatusCode::UNPROCESSABLE_ENTITY, report.to_string()).into_response()
            }
            _ => StatusCode::INTERNAL_SERVER_ERROR.into_response(),
        }
    }
}

impl From<FilterError> for HandlerError {
    fn from(err: FilterError) -> Self {
        match err {
            FilterError::Parse(e) => HandlerError::Other(anyhow::anyhow!(e)),
            FilterError::Validation(report) => HandlerError::Validation(report),
        }
    }
}
