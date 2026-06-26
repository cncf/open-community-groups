//! HTTP handlers for the public sponsor inquiry page.

use askama::Template;
use axum::{
    extract::State,
    http::Uri,
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    auth::AuthSession,
    db::DynDB,
    handlers::{error::HandlerError, extractors::ValidatedForm},
    router::PUBLIC_SHARED_CACHE_HEADERS,
    services::notifications::{DynNotificationsManager, OutboundEmail},
    templates::{
        PageId,
        auth::User,
        site::sponsor::{Page, SPONSOR_INQUIRY_RECIPIENT, SponsorInquiry},
    },
};

#[cfg(test)]
mod tests;

/// Handler that renders the public sponsor inquiry page.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    Ok((
        PUBLIC_SHARED_CACHE_HEADERS,
        Html(render_page(auth_session, &db, uri.path(), false).await?),
    ))
}

/// Handler that sends the public sponsor inquiry.
#[instrument(skip_all, err)]
pub(crate) async fn submit(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    ValidatedForm(input): ValidatedForm<SponsorInquiry>,
) -> Result<impl IntoResponse, HandlerError> {
    let email = OutboundEmail {
        body: input.email_body(),
        subject: input.email_subject(),
        to: SPONSOR_INQUIRY_RECIPIENT.to_string(),
    };
    notifications_manager.send_email(&email).await?;

    Ok((
        PUBLIC_SHARED_CACHE_HEADERS,
        Html(render_page(auth_session, &db, "/sponsor", true).await?),
    ))
}

async fn render_page(
    auth_session: AuthSession,
    db: &DynDB,
    path: &str,
    submitted: bool,
) -> Result<String, HandlerError> {
    let template = Page {
        submitted,
        page_id: PageId::SiteSponsor,
        path: path.to_string(),
        site_settings: db.get_site_settings().await?,
        user: User::from_session(auth_session).await?,
    };

    Ok(template.render()?)
}
