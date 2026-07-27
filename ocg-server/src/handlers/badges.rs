//! Public Open Badges credential, issuer, status, and verification handlers.

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
    router::{CACHE_CONTROL_NO_STORE, PUBLIC_SHARED_CACHE_HEADERS},
    services::badges::{
        BadgesManager, BadgesManagerError, CID_CONTEXT_URL, MULTIKEY_CONTEXT_URL,
        OPEN_BADGES_CONTEXT_URL, png,
    },
    templates::badges::{CredentialPage, VerifiedBadgeView, VerifyPage},
};

#[cfg(test)]
mod tests;

/// Request headers used to vary cached credential responses.
const CREDENTIAL_CACHE_VARY: &str = "x-ocg-commit-sha, hx-request, x-ocg-fetch, accept";

/// User-facing message returned for invalid badge submissions.
const INVALID_VERIFICATION_MESSAGE: &str =
    "This badge could not be verified as an OCG-issued credential.";

/// Cache policy for immutable content-addressed issuer key documents.
const ISSUER_KEY_CACHE_CONTROL: &str = "public, max-age=31536000, immutable";

/// Cache policy for signed status list credentials.
const STATUS_LIST_CACHE_CONTROL: &str = "public, max-age=600";

/// Default and maximum number of badges returned by one public profile request.
const USER_PROFILE_BADGES_LIMIT: usize = 50;

// Pages handlers.

/// Serve the public credential page or signed JSON-LD representation.
#[instrument(skip_all, err)]
pub(crate) async fn credential(
    State(badges_manager): State<Arc<BadgesManager>>,
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

    // Serve the signed JSON-LD credential when the client asks for it
    if accepts_credential(&headers) {
        // Reuse the immutable signature and shed excess cold-signing load
        let credential = match badges_manager.cached_credential(&award).await {
            Ok(credential) => credential,
            Err(BadgesManagerError::Busy) => {
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
    let image_url = badge_image_url(&award.snapshot.image_file_name);
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

/// Render the public badge verification form.
#[instrument(skip_all, err)]
pub(crate) async fn verify_page(
    State(db): State<DynDB>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    render_verify_page(&db, uri.path(), None, None).await
}

// JSON handlers.

/// Publish a stable group issuer profile.
#[instrument(skip_all, err)]
pub(crate) async fn issuer(
    State(badges_manager): State<Arc<BadgesManager>>,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Derive every retained verification method for this issuer controller
    let verification_methods = badges_manager
        .verification_methods(group_id)
        .map_err(|error| HandlerError::Other(error.into()))?;
    let assertion_methods = verification_methods
        .iter()
        .map(|method| method.id.to_string())
        .collect::<Vec<_>>();

    // Publish the issuer as a JSON-LD controller document with its identity,
    // verification methods, and assertion relationship
    Ok((
        PUBLIC_SHARED_CACHE_HEADERS,
        Json(json!({
            "@context": [CID_CONTEXT_URL, OPEN_BADGES_CONTEXT_URL],
            "id": badges_manager.issuer_url(group_id),
            "type": ["Profile"],
            "name": BadgesManager::issuer_name(group_id),
            "assertionMethod": assertion_methods,
            "verificationMethod": verification_methods
        })),
    ))
}

/// Publish one retained issuer verification key as a Multikey document.
#[instrument(skip_all, err)]
pub(crate) async fn issuer_key(
    State(badges_manager): State<Arc<BadgesManager>>,
    Path((group_id, key_multibase)): Path<(Uuid, String)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Resolve the retained verification method addressed by this key
    let method = badges_manager
        .verification_method(group_id, &key_multibase)
        .map_err(|error| match error {
            BadgesManagerError::UnknownVerificationMethod => HandlerError::NotFound,
            error => HandlerError::Other(error.into()),
        })?;

    // Publish the immutable content-addressed Multikey document
    Ok((
        [(CACHE_CONTROL, ISSUER_KEY_CACHE_CONTROL)],
        Json(json!({
            "@context": MULTIKEY_CONTEXT_URL,
            "id": method.id.as_str(),
            "type": "Multikey",
            "controller": method.controller.as_str(),
            "publicKeyMultibase": method.public_key.encoded.as_str()
        })),
    ))
}

/// Publish a signed revocation-only Bitstring Status List credential.
#[instrument(skip_all, err)]
pub(crate) async fn status_list(
    State(badges_manager): State<Arc<BadgesManager>>,
    State(db): State<DynDB>,
    Path(badge_status_list_id): Path<Uuid>,
) -> Result<Response, HandlerError> {
    // Resolve current revocation state and reuse or sign its stable list
    let status = db
        .get_badge_status_list(badge_status_list_id)
        .await?
        .ok_or(HandlerError::NotFound)?;
    let credential = badges_manager
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

/// Return active, listed badges for a user across all communities.
#[instrument(skip_all, err)]
pub(crate) async fn user_profile_badges(
    State(db): State<DynDB>,
    Path(username): Path<String>,
    Query(query): Query<UserProfileBadgesQuery>,
) -> Result<impl IntoResponse, HandlerError> {
    // Validate the requested page stays within the public response cap
    let limit = query.limit.unwrap_or(USER_PROFILE_BADGES_LIMIT);
    let offset = query.offset.unwrap_or_default();
    if limit == 0 || limit > USER_PROFILE_BADGES_LIMIT || i32::try_from(offset).is_err() {
        return Err(HandlerError::Deserialization(
            "badge pagination is outside the supported range".to_string(),
        ));
    }

    // List the user's public profile badges across all communities
    let badges = db.list_user_public_badges(limit, offset, &username).await?;

    Ok((PUBLIC_SHARED_CACHE_HEADERS, Json(badges)))
}

// Actions handlers.

/// Verify one ID, credential URL, or bounded Open Badges PNG.
#[instrument(skip_all, err)]
pub(crate) async fn verify(
    State(badges_manager): State<Arc<BadgesManager>>,
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
        &badges_manager,
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

/// Builds the public URL for stored badge artwork.
fn badge_image_url(image_file_name: &str) -> String {
    format!("/images/badges/{image_file_name}")
}

/// Classify proof/profile failures without hiding server configuration faults.
fn map_verification_validation_error(error: BadgesManagerError) -> VerificationError {
    match error {
        error @ (BadgesManagerError::InvalidContext | BadgesManagerError::InvalidKey) => {
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
    badges_manager: &BadgesManager,
    db: &DynDB,
    credential_reference: Option<&str>,
    png_bytes: Option<&[u8]>,
) -> Result<VerifiedBadgeView, VerificationError> {
    // Verify and bind an uploaded portable credential to its persisted award
    if let Some(png_bytes) = png_bytes {
        let credential = png::extract(png_bytes).map_err(|_| VerificationError::Invalid)?;
        let credential =
            serde_json::from_slice::<Value>(&credential).map_err(|_| VerificationError::Invalid)?;
        let verified = badges_manager
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

        // Flag exports whose identity no longer matches the durable binding
        let superseded = verified.email_identity.as_ref().is_some_and(|identity| {
            award.identity_hash.as_deref() != Some(identity.identity_hash.as_str())
                || award.identity_salt.as_deref() != Some(identity.salt.as_str())
        });

        return Ok(VerifiedBadgeView {
            description: verified.description,
            image_url: badge_image_url(&award.snapshot.image_file_name),
            issuer: verified.issuer,
            name: verified.name,
            revoked: award.revoked_at.is_some(),
            superseded,
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
        .or_else(|_| badges_manager.parse_credential_url(reference))
        .map_err(|_| VerificationError::Invalid)?;
    let award = db
        .get_public_user_badge(user_badge_id)
        .await
        .map_err(VerificationError::Internal)?
        .ok_or(VerificationError::Invalid)?;

    Ok(VerifiedBadgeView {
        description: award.snapshot.description,
        image_url: badge_image_url(&award.snapshot.image_file_name),
        issuer: badges_manager.issuer_url(award.group_id),
        name: award.snapshot.name,
        revoked: award.revoked_at.is_some(),
        superseded: false,
        valid_from: award.awarded_at,

        recipient_name: recipient_display_name(award.recipient_name, award.recipient_username),
    })
}
