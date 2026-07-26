//! User dashboard badge listing, ordering, revocation, and export handlers.

use std::sync::Arc;

use anyhow::Result;
use askama::Template;
use axum::{
    Json,
    extract::{Path, State},
    http::{HeaderMap, HeaderValue, StatusCode, header::CONTENT_DISPOSITION, header::CONTENT_TYPE},
    response::{Html, IntoResponse, Response},
};
use chrono::Utc;
use serde::Deserialize;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extractors::CurrentUser},
    services::{
        badges::{BadgesManager, CredentialInput, EmailIdentity, png},
        images::DynImageStorage,
    },
    templates::dashboard::user::badges::ListPage,
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Export one active owned badge as a PNG containing its signed credential.
#[instrument(skip_all, err)]
pub(crate) async fn export(
    CurrentUser(user): CurrentUser,
    State(badges_manager): State<Arc<BadgesManager>>,
    State(db): State<DynDB>,
    State(image_storage): State<DynImageStorage>,
    Path(user_badge_id): Path<Uuid>,
) -> Result<Response, HandlerError> {
    // Resolve an active owned award and its immutable source artwork
    let award = db
        .get_user_badge(user.user_id, user_badge_id)
        .await?
        .filter(|award| award.revoked_at.is_none())
        .ok_or(HandlerError::NotFound)?;
    let source = image_storage
        .get(&award.snapshot.image_file_name)
        .await?
        .ok_or(HandlerError::NotFound)?;

    // Issue the signed credential bound to the owner's account email and bake
    // it into a bounded PNG so importers such as Credly can match the owner
    let credential = badges_manager
        .issue_credential(CredentialInput {
            award: &award,
            created_at: Utc::now(),
            email_identity: Some(EmailIdentity::new(&user.email)),
        })
        .await
        .map_err(|error| HandlerError::Other(error.into()))?;
    let credential = serde_json::to_vec(&credential)?;
    let png =
        png::bake(&source.bytes, &credential).map_err(|error| HandlerError::Other(error.into()))?;

    // Return a deterministic attachment name for the opaque award ID
    let mut headers = HeaderMap::new();
    headers.insert(CONTENT_TYPE, HeaderValue::from_static("image/png"));
    headers.insert(
        CONTENT_DISPOSITION,
        HeaderValue::from_str(&format!(
            "attachment; filename=\"badge-{user_badge_id}.png\""
        ))
        .map_err(|error| HandlerError::Other(error.into()))?,
    );

    Ok((headers, png).into_response())
}

/// Render the active user badge list.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Render active awards through the shared page preparation path
    Ok(Html(prepare_list_page(&db, user.user_id).await?.render()?))
}

// Actions handlers.

/// Permanently revoke one active badge owned by the current user.
#[instrument(skip_all, err)]
pub(crate) async fn revoke(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(user_badge_id): Path<Uuid>,
) -> Result<StatusCode, HandlerError> {
    // Permanently revoke the active owned credential
    db.revoke_user_badge(user.user_id, user_badge_id).await?;

    Ok(StatusCode::NO_CONTENT)
}

/// Persist whether a badge is discoverable on public profiles.
#[instrument(skip_all, err)]
pub(crate) async fn update_listing(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(user_badge_id): Path<Uuid>,
    Json(input): Json<ListingInput>,
) -> Result<StatusCode, HandlerError> {
    // Persist profile visibility only for an active owned credential
    db.update_user_badge_listing(user.user_id, user_badge_id, input.is_listed)
        .await?;

    Ok(StatusCode::NO_CONTENT)
}

/// Persist a complete keyboard or pointer-generated badge order.
#[instrument(skip_all, err)]
pub(crate) async fn update_order(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Json(input): Json<OrderInput>,
) -> Result<StatusCode, HandlerError> {
    // Persist the complete active order atomically
    db.update_user_badges_order(user.user_id, &input.user_badge_ids)
        .await?;

    Ok(StatusCode::NO_CONTENT)
}

// Types.

/// Profile listing request body.
#[derive(Debug, Deserialize)]
pub(crate) struct ListingInput {
    /// Whether public profiles should discover the badge.
    is_listed: bool,
}

/// Badge ordering request body.
#[derive(Debug, Deserialize)]
pub(crate) struct OrderInput {
    /// Complete active badge order.
    user_badge_ids: Vec<Uuid>,
}

// Helpers.

/// Prepare the active badge list for the dashboard shell and partial route.
pub(crate) async fn prepare_list_page(db: &DynDB, user_id: Uuid) -> Result<ListPage, HandlerError> {
    // Load only active awards owned by the dashboard user
    Ok(ListPage {
        badges: db.list_user_badges(user_id).await?,
    })
}
