//! Public Open Badges credential, status, key, issuer, and verification handlers.

use std::sync::Arc;

use askama::Template;
use axum::{
    Json,
    extract::{Multipart, Path, Query, State},
    http::{
        HeaderMap, StatusCode, Uri, header::ACCEPT, header::CACHE_CONTROL, header::CONTENT_TYPE,
        header::RETRY_AFTER,
    },
    response::{Html, IntoResponse, Response},
};
use chrono::Utc;
use serde::Deserialize;
use serde_json::{Value, json};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extend_public_shared_cache_headers},
    router::{CACHE_CONTROL_IMMUTABLE, CACHE_CONTROL_NO_STORE, PUBLIC_SHARED_CACHE_HEADERS},
    services::badges::{BadgeService, BadgeServiceError, png, rfc3339},
    templates::badges::{CredentialPage, VerifiedBadgeView, VerifyPage},
};

#[cfg(test)]
mod tests;

/// Request headers used to vary cached credential responses.
const CREDENTIAL_CACHE_VARY: &str = "x-ocg-commit-sha, hx-request, x-ocg-fetch, accept";
/// User-facing message returned for invalid badge submissions.
const INVALID_VERIFICATION_MESSAGE: &str =
    "This badge could not be verified as an OCG-issued credential.";
/// Cache policy for signed status list credentials.
const STATUS_LIST_CACHE_CONTROL: &str = "public, max-age=600";
/// Default and maximum number of badges returned by one public profile request.
const USER_PROFILE_BADGES_LIMIT: usize = 50;

// Pages handlers.

/// Serve the public credential page or signed JSON-LD representation.
#[instrument(skip_all, err)]
pub(crate) async fn credential(
    State(badge_service): State<Arc<BadgeService>>,
    State(db): State<DynDB>,
    Path(user_badge_id): Path<Uuid>,
    headers: HeaderMap,
    uri: Uri,
) -> Result<Response, HandlerError> {
    // Resolve the durable public award snapshot
    let award = db
        .get_public_user_badge(user_badge_id)
        .await?
        .ok_or(HandlerError::NotFound)?;

    if accepts_credential(&headers) {
        // Reuse the immutable signature and shed excess cold-signing load
        let credential = match badge_service.cached_credential(&award, Utc::now()).await {
            Ok(credential) => credential,
            Err(BadgeServiceError::Busy) => {
                return Ok((
                    StatusCode::SERVICE_UNAVAILABLE,
                    [(CACHE_CONTROL, CACHE_CONTROL_NO_STORE), (RETRY_AFTER, "1")],
                )
                    .into_response());
            }
            Err(error) => return Err(HandlerError::Other(error.into())),
        };
        let cache_headers = extend_public_shared_cache_headers(&[
            ("content-type", "application/vc+ld+json"),
            ("vary", CREDENTIAL_CACHE_VARY),
        ])?;
        return Ok((cache_headers, Json(credential)).into_response());
    }

    // Render the browser representation from the same snapshot
    let site_settings = db.get_site_settings().await?;
    let image_url = format!("/images/badges/{}", award.snapshot.image_file_name);
    let revoked = award.revoked_at.is_some();
    let page = CredentialPage {
        award,
        image_url,
        path: uri.path().to_string(),
        revoked,
        site_settings,
    };

    let cache_headers = extend_public_shared_cache_headers(&[("vary", CREDENTIAL_CACHE_VARY)])?;
    Ok((cache_headers, Html(page.render()?)).into_response())
}

/// Publish a stable group issuer profile.
#[instrument(skip_all)]
pub(crate) async fn issuer(
    State(badge_service): State<Arc<BadgeService>>,
    Path(group_id): Path<Uuid>,
) -> impl IntoResponse {
    // Publish every retained assertion method on the stable issuer profile
    let assertion_methods = badge_service
        .verification_key_ids()
        .into_iter()
        .filter_map(|key_id| {
            badge_service
                .verification_method(key_id)
                .ok()?
                .get("id")?
                .as_str()
                .map(str::to_string)
        })
        .collect::<Vec<_>>();
    (
        PUBLIC_SHARED_CACHE_HEADERS,
        Json(json!({
            "id": badge_service.issuer_url(group_id),
            "type": "Profile",
            "name": format!("Open Community Groups issuer {group_id}"),
            "assertionMethod": assertion_methods
        })),
    )
}

/// Publish a signed revocation-only Bitstring Status List credential.
#[instrument(skip_all, err)]
pub(crate) async fn status_list(
    State(badge_service): State<Arc<BadgeService>>,
    State(db): State<DynDB>,
    Path(badge_status_list_id): Path<Uuid>,
) -> Result<Response, HandlerError> {
    // Resolve current revocation state and reuse or sign its stable list
    let status = db
        .get_badge_status_list(badge_status_list_id)
        .await?
        .ok_or(HandlerError::NotFound)?;
    let credential = badge_service
        .cached_status_list(
            status.badge_status_list_id,
            status.group_id,
            &status.revoked_indexes,
            Utc::now(),
        )
        .await
        .map_err(|error| HandlerError::Other(error.into()))?;

    Ok((
        [
            (CONTENT_TYPE, "application/vc+ld+json"),
            (CACHE_CONTROL, STATUS_LIST_CACHE_CONTROL),
        ],
        Json(credential),
    )
        .into_response())
}

/// Return active, listed badges for a user in one community.
#[instrument(skip_all, err)]
pub(crate) async fn user_profile_badges(
    State(db): State<DynDB>,
    Path((community_name, username)): Path<(String, String)>,
    Query(query): Query<UserProfileBadgesQuery>,
) -> Result<impl IntoResponse, HandlerError> {
    let limit = query.limit.unwrap_or(USER_PROFILE_BADGES_LIMIT);
    let offset = query.offset.unwrap_or_default();
    if limit == 0 || limit > USER_PROFILE_BADGES_LIMIT || i32::try_from(offset).is_err() {
        return Err(HandlerError::Deserialization(
            "badge pagination is outside the supported range".to_string(),
        ));
    }

    // Resolve the community boundary before returning its public projection
    let community_id = db
        .get_community_id_by_name(&community_name)
        .await?
        .ok_or(HandlerError::NotFound)?;
    let badges = db
        .list_user_public_badges(community_id, limit, offset, &username)
        .await?;

    Ok((PUBLIC_SHARED_CACHE_HEADERS, Json(badges)))
}

/// Publish one allowlisted Ed25519 Multikey verification method.
#[instrument(skip_all)]
pub(crate) async fn verification_key(
    State(badge_service): State<Arc<BadgeService>>,
    Path(key_id): Path<String>,
) -> Response {
    match badge_service.verification_method(&key_id) {
        Ok(method) => ([(CACHE_CONTROL, CACHE_CONTROL_IMMUTABLE)], Json(method)).into_response(),
        Err(_) => StatusCode::NOT_FOUND.into_response(),
    }
}

/// Render the public badge verification form.
#[instrument(skip_all, err)]
pub(crate) async fn verify_page(
    State(db): State<DynDB>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    render_verify_page(&db, uri.path(), None, None).await
}

// Actions handlers.

/// Verify one ID, credential URL, or bounded Open Badges PNG.
#[instrument(skip_all, err)]
pub(crate) async fn verify(
    State(badge_service): State<Arc<BadgeService>>,
    State(db): State<DynDB>,
    uri: Uri,
    mut multipart: Multipart,
) -> Result<impl IntoResponse, HandlerError> {
    // Collect only the supported local reference or bounded PNG fields
    let mut credential_reference = None;
    let mut png_bytes = None;
    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|error| HandlerError::Other(error.into()))?
    {
        match field.name() {
            Some("credential") => {
                credential_reference = Some(
                    field
                        .text()
                        .await
                        .map_err(|error| HandlerError::Other(error.into()))?,
                );
            }
            Some("png") if field.file_name().is_some() => {
                png_bytes = Some(
                    field
                        .bytes()
                        .await
                        .map_err(|error| HandlerError::Other(error.into()))?,
                );
            }
            _ => {}
        }
    }

    // Verify the local credential and preserve operational error classes
    let result = verify_submission(
        &badge_service,
        &db,
        credential_reference.as_deref(),
        png_bytes.as_deref(),
    )
    .await;
    match result {
        Ok(result) => render_verify_page(&db, uri.path(), Some(result), None).await,
        Err(VerificationError::Invalid) => {
            render_verify_page(
                &db,
                uri.path(),
                None,
                Some(INVALID_VERIFICATION_MESSAGE.to_string()),
            )
            .await
        }
        Err(VerificationError::Internal(error)) => Err(HandlerError::Other(error)),
    }
}

// Types.

/// Pagination accepted by the public profile badge endpoint.
#[derive(Debug, Default, Deserialize)]
pub(crate) struct UserProfileBadgesQuery {
    /// Requested page size.
    limit: Option<usize>,
    /// Requested result offset.
    offset: Option<usize>,
}

/// Expected invalid input or an operational verification failure.
#[derive(Debug, thiserror::Error)]
enum VerificationError {
    /// User-supplied input is malformed, unknown, or cryptographically invalid.
    #[error("invalid badge credential")]
    Invalid,
    /// Server or database state prevented verification from completing.
    #[error(transparent)]
    Internal(anyhow::Error),
}

// Helpers.

/// Return whether the client requested the JSON-LD credential representation.
fn accepts_credential(headers: &HeaderMap) -> bool {
    headers
        .get_all(ACCEPT)
        .iter()
        .filter_map(|value| value.to_str().ok())
        .flat_map(|value| value.split(','))
        .any(|item| {
            let mut parts = item.split(';').map(str::trim);
            let supported = parts.next().is_some_and(|media_type| {
                media_type.eq_ignore_ascii_case("application/vc+ld+json")
            });
            let quality = parts
                .filter_map(|parameter| parameter.split_once('='))
                .find(|(name, _)| name.trim().eq_ignore_ascii_case("q"))
                .map_or(1.0, |(_, value)| value.trim().parse::<f32>().unwrap_or(0.0));
            supported && quality > 0.0
        })
}

/// Classify proof/profile failures without hiding server configuration faults.
fn map_verification_validation_error(error: BadgeServiceError) -> VerificationError {
    match error {
        error @ (BadgeServiceError::InvalidContext | BadgeServiceError::InvalidKey) => {
            VerificationError::Internal(error.into())
        }
        _ => VerificationError::Invalid,
    }
}

/// Prefer a public name while retaining the public username fallback.
fn recipient_display_name(name: Option<String>, username: Option<String>) -> Option<String> {
    name.or(username)
}

/// Render the verification page with an optional result.
async fn render_verify_page(
    db: &DynDB,
    path: &str,
    verified: Option<VerifiedBadgeView>,
    error: Option<String>,
) -> Result<Response, HandlerError> {
    // Render an uncached result because recipient information may be present
    let page = VerifyPage {
        path: path.to_string(),
        site_settings: db.get_site_settings().await?,

        error,
        verified,
    };
    Ok((
        [(CACHE_CONTROL, CACHE_CONTROL_NO_STORE)],
        Html(page.render()?),
    )
        .into_response())
}

/// Resolve and verify one supported form submission without arbitrary dereferencing.
async fn verify_submission(
    badge_service: &BadgeService,
    db: &DynDB,
    credential_reference: Option<&str>,
    png_bytes: Option<&[u8]>,
) -> Result<VerifiedBadgeView, VerificationError> {
    // Verify and bind an uploaded portable credential to its persisted award
    if let Some(png_bytes) = png_bytes {
        let credential = png::extract(png_bytes).map_err(|_| VerificationError::Invalid)?;
        let credential =
            serde_json::from_slice::<Value>(&credential).map_err(|_| VerificationError::Invalid)?;
        let verified = badge_service
            .verify_credential(&credential)
            .await
            .map_err(map_verification_validation_error)?;
        let award = db
            .get_public_user_badge(verified.user_badge_id)
            .await
            .map_err(VerificationError::Internal)?
            .ok_or(VerificationError::Invalid)?;
        if award.badge_status_list_id != verified.status_list_id
            || award.group_id != verified.group_id
            || award.status_list_index != verified.status_list_index
        {
            return Err(VerificationError::Invalid);
        }

        return Ok(VerifiedBadgeView {
            description: verified.description,
            issuer: verified.issuer,
            name: verified.name,
            revoked: award.revoked_at.is_some(),
            valid_from: verified.valid_from,

            recipient_name: recipient_display_name(award.recipient_name, award.recipient_username),
        });
    }

    // Resolve a local reference directly from durable award state
    let reference = credential_reference
        .map(str::trim)
        .filter(|reference| !reference.is_empty())
        .ok_or(VerificationError::Invalid)?;
    let user_badge_id = Uuid::parse_str(reference)
        .or_else(|_| badge_service.parse_credential_url(reference))
        .map_err(|_| VerificationError::Invalid)?;
    let award = db
        .get_public_user_badge(user_badge_id)
        .await
        .map_err(VerificationError::Internal)?
        .ok_or(VerificationError::Invalid)?;

    Ok(VerifiedBadgeView {
        description: award.snapshot.description,
        issuer: badge_service.issuer_url(award.group_id),
        name: award.snapshot.name,
        revoked: award.revoked_at.is_some(),
        valid_from: rfc3339(award.awarded_at),

        recipient_name: recipient_display_name(award.recipient_name, award.recipient_username),
    })
}
