//! HTTP handlers for the Credentials section in the group dashboard.
//!
//! Stateless CertDirectory integration: organizers supply an API key + badge ID
//! from the browser (localStorage). The server resolves attendee emails and
//! calls CertDirectory; emails never reach the browser.

use std::collections::HashMap;

use askama::Template;
use axum::{
    Json,
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
    response::{Html, IntoResponse},
};
use serde::{Deserialize, Serialize};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedCommunityId, SelectedGroupId},
    },
    services::credentials::{CredentialsClient, CredentialsError, friendly},
    templates::dashboard::group::{
        attendees::{Attendee, AttendeesFilters},
        credentials,
    },
    types::{event::EventSummary, permissions::GroupPermission},
};

/// Header carrying the CertDirectory API key (from browser localStorage).
const HEADER_API_KEY: &str = "x-cd-api-key";
/// Header carrying the CertDirectory badge / achievement UUID.
const HEADER_BADGE_ID: &str = "x-cd-badge-id";

/// Displays the Credentials tab for a specific event.
#[instrument(skip_all, err)]
pub(crate) async fn tab_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    let filters = AttendeesFilters::default();
    let (can_manage_events, event, search_attendees_results) = tokio::try_join!(
        db.user_has_group_permission(
            &community_id,
            &group_id,
            &user.user_id,
            GroupPermission::EventsWrite
        ),
        db.get_event_summary(community_id, group_id, event_id),
        // Default filters → LIMIT NULL → all attendees (needed for status matching).
        db.search_event_attendees(group_id, event_id, &filters)
    )?;

    let template = credentials::ListPage {
        attendees: search_attendees_results.attendees,
        can_manage_events,
        event,
        group_id,
        total: search_attendees_results.total,
    };

    Ok(Html(template.render()?))
}

/// Validate API key + badge ID against CertDirectory and return the badge name.
#[instrument(skip_all, err)]
pub(crate) async fn validate(
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(cred): State<CredentialsClient>,
    Path(event_id): Path<Uuid>,
    headers: HeaderMap,
) -> Result<impl IntoResponse, HandlerError> {
    let _: EventSummary = db.get_event_summary(community_id, group_id, event_id).await?;

    let (api_key, badge_id) = match read_cred_headers(&headers) {
        Ok(v) => v,
        Err(msg) => return Ok((StatusCode::BAD_REQUEST, msg).into_response()),
    };

    match cred.get_badge(&api_key, &badge_id).await {
        Ok(badge) => Ok(Json(ValidateRow {
            badge_id: badge.id,
            badge_name: badge.name,
            is_active: badge.is_active,
        })
        .into_response()),
        Err(e) => Ok((StatusCode::BAD_GATEWAY, friendly(&e)).into_response()),
    }
}

/// Derive live issuance status for each attendee (matched by email server-side).
///
/// Response contains `user_id` + status only — never emails.
#[instrument(skip_all, err)]
pub(crate) async fn status(
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(cred): State<CredentialsClient>,
    Path(event_id): Path<Uuid>,
    headers: HeaderMap,
) -> Result<impl IntoResponse, HandlerError> {
    // Ensure the event belongs to the selected group (permission is enforced by
    // the EventsWrite route layer).
    let _: EventSummary = db.get_event_summary(community_id, group_id, event_id).await?;

    let (api_key, badge_id) = match read_cred_headers(&headers) {
        Ok(v) => v,
        Err(msg) => return Ok((StatusCode::BAD_REQUEST, msg).into_response()),
    };

    let filters = AttendeesFilters::default();
    let attendees = db
        .search_event_attendees(group_id, event_id, &filters)
        .await?;

    let issued = match cred.list_by_badge(&api_key, &badge_id).await {
        Ok(list) => list,
        Err(e) => {
            return Ok((StatusCode::BAD_GATEWAY, friendly(&e)).into_response());
        }
    };

    let by_email: HashMap<String, &crate::services::credentials::ListedCredential> = issued
        .iter()
        .map(|c| (c.email.to_lowercase(), c))
        .collect();

    let rows: Vec<StatusRow> = attendees
        .attendees
        .iter()
        .map(|a| {
            let match_cred = by_email.get(&a.email.to_lowercase());
            StatusRow {
                user_id: a.user.user_id,
                status: match_cred
                    .map(|c| map_cd_status(&c.status))
                    .unwrap_or_else(|| "not_issued".to_string()),
                eligible: a.can_receive_attendee_email,
                verify_url: match_cred.map(|c| c.verify_url.clone()),
                credential_id: match_cred.map(|c| c.credential_id.clone()),
            }
        })
        .collect();

    Ok(Json(rows).into_response())
}

/// Issue a credential to a single attendee.
#[instrument(skip_all, err)]
pub(crate) async fn issue_one(
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(cred): State<CredentialsClient>,
    Path((event_id, user_id)): Path<(Uuid, Uuid)>,
    headers: HeaderMap,
) -> Result<impl IntoResponse, HandlerError> {
    let _: EventSummary = db.get_event_summary(community_id, group_id, event_id).await?;

    let (api_key, badge_id) = match read_cred_headers(&headers) {
        Ok(v) => v,
        Err(msg) => return Ok((StatusCode::BAD_REQUEST, msg).into_response()),
    };

    let filters = AttendeesFilters::default();
    let attendees = db
        .search_event_attendees(group_id, event_id, &filters)
        .await?;
    let Some(attendee) = attendees
        .attendees
        .into_iter()
        .find(|a| a.user.user_id == user_id)
    else {
        return Ok((StatusCode::NOT_FOUND, "attendee not found").into_response());
    };

    if !attendee.can_receive_attendee_email {
        return Ok((
            StatusCode::BAD_REQUEST,
            "attendee is not eligible to receive credentials (email opt-in / verification)",
        )
            .into_response());
    }

    // No re-issue (locked decision): if any credential already exists for this
    // email+badge, treat as already issued and do not call the issue API.
    match cred.list_by_badge(&api_key, &badge_id).await {
        Ok(list) => {
            let email_lc = attendee.email.to_lowercase();
            if let Some(existing) = list.iter().find(|c| c.email == email_lc) {
                return Ok(Json(IssueRow {
                    user_id,
                    status: map_cd_status(&existing.status),
                    verify_url: Some(existing.verify_url.clone()),
                    credential_id: Some(existing.credential_id.clone()),
                    error: None,
                })
                .into_response());
            }
        }
        Err(e) => {
            return Ok((StatusCode::BAD_GATEWAY, friendly(&e)).into_response());
        }
    }

    let name = display_name(&attendee);
    match cred
        .issue(&api_key, &badge_id, &name, &attendee.email)
        .await
    {
        Ok(r) => Ok(Json(IssueRow {
            user_id,
            status: map_cd_status(&r.status),
            verify_url: Some(r.verify_url),
            credential_id: Some(r.credential_id),
            error: None,
        })
        .into_response()),
        Err(CredentialsError::Duplicate) => Ok(Json(IssueRow {
            user_id,
            status: "issued".to_string(),
            verify_url: None,
            credential_id: None,
            error: None,
        })
        .into_response()),
        Err(e) => Ok(Json(IssueRow {
            user_id,
            status: "failed".to_string(),
            verify_url: None,
            credential_id: None,
            error: Some(friendly(&e)),
        })
        .into_response()),
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn read_cred_headers(headers: &HeaderMap) -> Result<(String, String), &'static str> {
    let api_key = headers
        .get(HEADER_API_KEY)
        .and_then(|v| v.to_str().ok())
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .ok_or("missing X-CD-Api-Key header")?;
    let badge_id = headers
        .get(HEADER_BADGE_ID)
        .and_then(|v| v.to_str().ok())
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .ok_or("missing X-CD-Badge-Id header")?;
    Ok((api_key.to_string(), badge_id.to_string()))
}

fn display_name(attendee: &Attendee) -> String {
    attendee
        .user
        .name
        .as_deref()
        .filter(|n| !n.trim().is_empty())
        .unwrap_or(attendee.user.username.as_str())
        .to_string()
}

/// Map CertDirectory status strings into the dashboard vocabulary.
///
/// Any known CD status counts as "already has a credential" for the UI
/// (button disabled). Unknown values fall through as-is.
fn map_cd_status(cd: &str) -> String {
    match cd {
        "valid" | "pending" => {
            // pending = issued, awaiting claim — still "issued" for the button.
            if cd == "pending" {
                "pending".to_string()
            } else {
                "issued".to_string()
            }
        }
        "expired" => "expired".to_string(),
        "revoked" => "revoked".to_string(),
        other => other.to_string(),
    }
}

/// Per-attendee status row returned to the browser (no emails).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct StatusRow {
    pub user_id: Uuid,
    pub status: String,
    pub eligible: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub verify_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub credential_id: Option<String>,
}

/// Result of validating API key + badge ID.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct ValidateRow {
    pub badge_id: String,
    pub badge_name: String,
    pub is_active: bool,
}

/// Result of a single-attendee issue call.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct IssueRow {
    pub user_id: Uuid,
    pub status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub verify_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub credential_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}
