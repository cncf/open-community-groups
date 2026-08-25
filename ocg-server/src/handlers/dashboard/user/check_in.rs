//! HTTP handlers for attendee check-in credentials.

use askama::Template;
use axum::{
    extract::{Path, State},
    http::{StatusCode, header::CACHE_CONTROL, header::CONTENT_TYPE},
    response::{Html, IntoResponse},
};
use qrcode::render::svg;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    auth::User,
    db::DynDB,
    handlers::{error::HandlerError, extractors::CurrentUser},
    templates::dashboard::user::check_in::ListPage,
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Returns the current user's check-in event list.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare the credential list and attendee display identity
    let template = prepare_list_page(&db, &user).await?;

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Returns an SVG containing the current user's attendee credential.
#[instrument(skip_all, err)]
pub(crate) async fn qr_code(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Resolve only the authenticated user's confirmed attendee credential
    let Some(check_in_code) = db.get_user_check_in_code(event_id, user.user_id).await? else {
        return Err(HandlerError::NotFound);
    };

    // Encode the versioned credential without placing it in a URL or log field
    let credential = format!("ocg-check-in:v1:{event_id}:{check_in_code}");
    let code = qrcode::QrCode::new(credential.as_bytes())
        .map_err(|err| anyhow::anyhow!("failed to generate attendee check-in QR code: {err}"))?;
    let svg = code
        .render()
        .min_dimensions(500, 500)
        .dark_color(svg::Color("#000000"))
        .light_color(svg::Color("#ffffff"))
        .build();

    // Prevent credential-bearing images from being cached
    Ok((
        StatusCode::OK,
        [
            (CACHE_CONTROL, "private, no-store"),
            (CONTENT_TYPE, "image/svg+xml"),
        ],
        svg,
    ))
}

// Helpers.

/// Prepares the user check-in list for full-page and fragment rendering.
pub(super) async fn prepare_list_page(db: &DynDB, user: &User) -> anyhow::Result<ListPage> {
    // Load the credential-bearing events without exposing their raw codes
    let events = db.list_user_check_in_events(user.user_id).await?;

    // Apply the username fallback used in the QR modal
    let name = if user.name.trim().is_empty() {
        user.username.clone()
    } else {
        user.name.clone()
    };

    Ok(ListPage {
        events,
        name,
        username: user.username.clone(),

        photo_url: user.photo_url.clone(),
    })
}
