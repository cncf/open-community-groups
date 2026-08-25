//! HTTP handlers for organizer attendee check-in scanning.

use anyhow::Error;
use askama::Template;
use axum::{
    Json,
    extract::{Path, State, rejection::JsonRejection},
    http::StatusCode,
    response::{Html, IntoResponse, Response},
};
use serde::Deserialize;
use serde_json::json;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedCommunityId, SelectedGroupId},
    },
    templates::dashboard::group::check_in::ListPage,
};

/// Maximum accepted serialized credential length.
const MAX_CREDENTIAL_LEN: usize = 160;

#[cfg(test)]
mod tests;

// Pages handlers.

/// Returns events available to the selected group's scanner.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare the narrow current and upcoming event list
    let template = prepare_list_page(&db, group_id).await?;

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Checks in an attendee using a scanned versioned credential.
#[instrument(skip_all, err)]
pub(crate) async fn scan(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
    input: Result<Json<ScanInput>, JsonRejection>,
) -> Result<Response, HandlerError> {
    // Validate the credential envelope before touching persistent state
    let Ok(Json(input)) = input else {
        return Ok(scan_error_response(
            StatusCode::BAD_REQUEST,
            "malformed-credential",
            "This QR code is not a valid check-in credential.",
        ));
    };
    let Ok((credential_event_id, check_in_code)) = parse_credential(&input.credential) else {
        return Ok(scan_error_response(
            StatusCode::BAD_REQUEST,
            "malformed-credential",
            "This QR code is not a valid check-in credential.",
        ));
    };
    if credential_event_id != event_id {
        return Ok(scan_error_response(
            StatusCode::UNPROCESSABLE_ENTITY,
            "wrong-event",
            "This credential belongs to a different event.",
        ));
    }

    // Resolve and apply the atomic check-in transition
    let result = match db
        .check_in_attendee_by_code(
            user.user_id,
            check_in_code,
            community_id,
            event_id,
            group_id,
        )
        .await
    {
        Ok(result) => result,
        Err(err) => {
            let Some(message) = database_error_message(&err) else {
                return Err(HandlerError::Other(err));
            };
            let Some(response) = scan_database_error_response(message) else {
                return Err(HandlerError::Other(err));
            };
            return Ok(response);
        }
    };

    // Return attendee context for visible and audible operator feedback
    Ok((StatusCode::OK, Json(result)).into_response())
}

// Types.

/// JSON body accepted by the scan endpoint.
#[derive(Debug, Deserialize)]
pub(crate) struct ScanInput {
    /// Full versioned credential decoded from the QR code.
    credential: String,
}

// Helpers.

/// Prepares the group check-in list for full-page and fragment rendering.
pub(super) async fn prepare_list_page(db: &DynDB, group_id: Uuid) -> anyhow::Result<ListPage> {
    // Load only events available to the selected group's scanner
    let events = db.list_group_check_in_events(group_id).await?;

    Ok(ListPage { events })
}

/// Returns the database exception message when `PostgreSQL` raised a domain error.
fn database_error_message(err: &Error) -> Option<&str> {
    err.downcast_ref::<tokio_postgres::Error>()?
        .as_db_error()
        .map(tokio_postgres::error::DbError::message)
}

/// Parses a versioned attendee credential into event and code identifiers.
fn parse_credential(credential: &str) -> Result<(Uuid, Uuid), ()> {
    if credential.len() > MAX_CREDENTIAL_LEN {
        return Err(());
    }

    let payload = credential.strip_prefix("ocg-check-in:v1:").ok_or(())?;
    let (event_id, check_in_code) = payload.split_once(':').ok_or(())?;
    if check_in_code.contains(':') {
        return Err(());
    }

    Ok((
        event_id.parse().map_err(|_| ())?,
        check_in_code.parse().map_err(|_| ())?,
    ))
}

/// Maps known database domain errors to typed scanner responses.
fn scan_database_error_response(message: &str) -> Option<Response> {
    match message {
        "attendance is not confirmed" => Some(scan_error_response(
            StatusCode::CONFLICT,
            "non-confirmed-attendance",
            "This attendee no longer has confirmed attendance.",
        )),
        "check-in credential not found" => Some(scan_error_response(
            StatusCode::UNPROCESSABLE_ENTITY,
            "unknown-code",
            "This check-in credential is not recognized.",
        )),
        "event unavailable for check-in" => Some(scan_error_response(
            StatusCode::CONFLICT,
            "unavailable-event",
            "This event is not available for check-in.",
        )),
        _ => None,
    }
}

/// Builds a typed scanner failure response.
fn scan_error_response(status: StatusCode, code: &'static str, message: &'static str) -> Response {
    (
        status,
        Json(json!({
            "error": {
                "code": code,
                "message": message,
            }
        })),
    )
        .into_response()
}
