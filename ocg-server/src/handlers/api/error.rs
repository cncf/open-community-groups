//! JSON API error responses.

use axum::{
    Json,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use serde::Serialize;

use crate::{handlers::error::HandlerError, types::search::FilterError};

/// Error type returned by API routes.
#[derive(Debug, thiserror::Error)]
#[error("{message}")]
pub(crate) struct ApiError {
    /// HTTP status.
    pub status: StatusCode,
    /// Machine-readable error code.
    pub code: &'static str,
    /// Human-readable error message.
    pub message: String,
    /// Optional error details.
    pub details: Vec<String>,
}

impl ApiError {
    /// Build a new API error.
    pub(crate) fn new(status: StatusCode, code: &'static str, message: impl Into<String>) -> Self {
        Self {
            status,
            code,
            message: message.into(),
            details: Vec::new(),
        }
    }

    /// Add details to an API error.
    pub(crate) fn with_details(mut self, details: Vec<String>) -> Self {
        self.details = details;
        self
    }

    /// 401 helper.
    pub(crate) fn unauthenticated() -> Self {
        Self::new(
            StatusCode::UNAUTHORIZED,
            "unauthenticated",
            "Authentication is required.",
        )
    }

    /// 403 helper.
    pub(crate) fn forbidden() -> Self {
        Self::new(
            StatusCode::FORBIDDEN,
            "forbidden",
            "You do not have permission to perform this action.",
        )
    }

    /// 404 helper.
    pub(crate) fn not_found() -> Self {
        Self::new(StatusCode::NOT_FOUND, "not_found", "Resource not found.")
    }
}

impl From<HandlerError> for ApiError {
    fn from(error: HandlerError) -> Self {
        match error {
            HandlerError::Auth(message) => {
                Self::new(StatusCode::UNAUTHORIZED, "unauthenticated", message)
            }
            HandlerError::Database(message) | HandlerError::Deserialization(message) => Self::new(
                StatusCode::UNPROCESSABLE_ENTITY,
                "validation_failed",
                message,
            ),
            HandlerError::Forbidden => Self::forbidden(),
            HandlerError::NotFound => Self::not_found(),
            HandlerError::Validation(report) => Self::new(
                StatusCode::UNPROCESSABLE_ENTITY,
                "validation_failed",
                "Request is invalid.",
            )
            .with_details(vec![report.to_string()]),
            _ => Self::new(
                StatusCode::INTERNAL_SERVER_ERROR,
                "internal_error",
                "An internal error occurred.",
            ),
        }
    }
}

impl From<FilterError> for ApiError {
    fn from(error: FilterError) -> Self {
        HandlerError::from(error).into()
    }
}

impl From<anyhow::Error> for ApiError {
    fn from(error: anyhow::Error) -> Self {
        HandlerError::from(error).into()
    }
}

impl From<tower_sessions::session::Error> for ApiError {
    fn from(_error: tower_sessions::session::Error) -> Self {
        Self::new(
            StatusCode::INTERNAL_SERVER_ERROR,
            "internal_error",
            "An internal error occurred.",
        )
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let status = self.status;
        (status, Json(ApiErrorEnvelope::from(self))).into_response()
    }
}

#[derive(Debug, Clone, Serialize)]
struct ApiErrorEnvelope {
    error: ApiErrorBody,
}

#[derive(Debug, Clone, Serialize)]
struct ApiErrorBody {
    code: &'static str,
    message: String,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    details: Vec<String>,
}

impl From<ApiError> for ApiErrorEnvelope {
    fn from(error: ApiError) -> Self {
        Self {
            error: ApiErrorBody {
                code: error.code,
                message: error.message,
                details: error.details,
            },
        }
    }
}
