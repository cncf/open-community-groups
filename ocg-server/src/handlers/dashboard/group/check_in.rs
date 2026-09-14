//! HTTP handlers for organizer attendee check-in scanning.

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
    services::check_in::{CheckInScanRejection, classify_scan_error, parse_credential},
    templates::dashboard::group::check_in::ListPage,
};

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
    let Ok(credential) = parse_credential(&input.credential) else {
        return Ok(scan_error_response(
            StatusCode::BAD_REQUEST,
            "malformed-credential",
            "This QR code is not a valid check-in credential.",
        ));
    };
    if credential.event_id != event_id {
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
            credential.check_in_code,
            community_id,
            event_id,
            group_id,
        )
        .await
    {
        Ok(result) => result,
        Err(err) => {
            let Some(rejection) = classify_scan_error(&err) else {
                return Err(HandlerError::from(err));
            };
            return Ok(scan_rejection_response(rejection));
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

/// Maps a stable scanner rejection to its typed response.
fn scan_rejection_response(rejection: CheckInScanRejection) -> Response {
    match rejection {
        CheckInScanRejection::NonConfirmedAttendance => scan_error_response(
            StatusCode::CONFLICT,
            "non-confirmed-attendance",
            "This attendee no longer has confirmed attendance.",
        ),
        CheckInScanRejection::UnavailableEvent => scan_error_response(
            StatusCode::CONFLICT,
            "unavailable-event",
            "This event is not available for check-in.",
        ),
        CheckInScanRejection::UnknownCode => scan_error_response(
            StatusCode::UNPROCESSABLE_ENTITY,
            "unknown-code",
            "This check-in credential is not recognized.",
        ),
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
