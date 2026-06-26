//! HTTP handlers for the public sponsor inquiry page.

use askama::Template;
use axum::{
    extract::State,
    http::{Uri, header::CACHE_CONTROL},
    response::{Html, IntoResponse, Redirect},
};
use tracing::instrument;

use crate::{
    auth::AuthSession,
    db::DynDB,
    handlers::{error::HandlerError, extractors::ValidatedForm},
    router::CACHE_CONTROL_PRIVATE_NO_STORE,
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
        [(CACHE_CONTROL, CACHE_CONTROL_PRIVATE_NO_STORE)],
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
    if auth_session.user.is_none() {
        return Ok(Redirect::to("/log-in?next_url=/sponsor").into_response());
    }

    let email = OutboundEmail {
        body: input.email_body(),
        subject: input.email_subject(),
        to: SPONSOR_INQUIRY_RECIPIENT.to_string(),
    };
    notifications_manager.send_email(&email).await?;

    Ok((
        [(CACHE_CONTROL, CACHE_CONTROL_PRIVATE_NO_STORE)],
        Html(render_page(auth_session, &db, "/sponsor", true).await?),
    )
        .into_response())
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
