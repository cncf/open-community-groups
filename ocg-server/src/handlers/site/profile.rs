//! HTTP handlers for shareable user profile cards.

use askama::Template;
use axum::{
    extract::{Path, State},
    http::{HeaderMap, StatusCode, Uri},
    response::{Html, IntoResponse, Redirect, Response},
};
use tracing::instrument;

use crate::{
    config::HttpServerConfig,
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, ValidatedForm},
        site::not_found,
    },
    router::PUBLIC_SHARED_CACHE_HEADERS,
    services::notifications::{DynNotificationsManager, OutboundEmail},
    templates::site::profile::{MentorshipRequestInput, MentorshipRequestRecord},
    templates::{PageId, auth::User, site::profile::Page},
};

/// Renders a public profile card by username.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    State(db): State<DynDB>,
    State(server_cfg): State<HttpServerConfig>,
    Path(username): Path<String>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    let (site_settings, profile) = tokio::try_join!(
        db.get_site_settings(),
        db.get_public_user_profile_by_username(&username)
    )?;
    let Some(profile) = profile else {
        return not_found::render(site_settings);
    };

    let template = Page {
        base_url: server_cfg.base_url,
        path: uri.path().to_string(),
        page_id: PageId::SiteHome,
        profile,
        mentorship_request_sent: uri
            .query()
            .is_some_and(|query| query.contains("mentorship=requested")),
        site_settings,
        user: User::default(),
    };

    Ok((PUBLIC_SHARED_CACHE_HEADERS, Html(template.render()?)).into_response())
}

/// Records a mentorship request and sends the mentor an email.
#[instrument(skip_all, err)]
pub(crate) async fn request_mentorship(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    Path(username): Path<String>,
    headers: HeaderMap,
    ValidatedForm(input): ValidatedForm<MentorshipRequestInput>,
) -> Result<Response, HandlerError> {
    if user.username.eq_ignore_ascii_case(&username) {
        return Ok(mentorship_request_alert(
            "You cannot request mentorship from yourself.",
            MentorshipRequestAlertKind::Error,
        )
        .into_response());
    }

    let request = db.add_mentorship_request(user.user_id, &username, &input).await?;
    let email = OutboundEmail {
        body: mentorship_request_email_body(&request),
        subject: mentorship_request_email_subject(&request),
        to: request.mentor_email.clone(),
    };
    notifications_manager.send_email(&email).await?;

    if is_htmx_request(&headers) {
        return Ok(mentorship_request_alert(
            "Mentorship request sent. The member will receive your details by email.",
            MentorshipRequestAlertKind::Success,
        )
        .into_response());
    }

    Ok(Redirect::to(&format!(
        "/profiles/{}?mentorship=requested#mentorship",
        request.mentor_username
    ))
    .into_response())
}

enum MentorshipRequestAlertKind {
    Error,
    Success,
}

fn mentorship_request_alert(message: &str, kind: MentorshipRequestAlertKind) -> impl IntoResponse {
    let class_name = match kind {
        MentorshipRequestAlertKind::Error => {
            "rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm font-semibold text-red-900"
        }
        MentorshipRequestAlertKind::Success => {
            "rounded-2xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm font-semibold text-emerald-900"
        }
    };

    (
        StatusCode::OK,
        Html(format!(
            r#"<div class="{class_name}" role="alert">{message}</div>"#
        )),
    )
}

fn is_htmx_request(headers: &HeaderMap) -> bool {
    headers
        .get("HX-Request")
        .and_then(|value| value.to_str().ok())
        .is_some_and(|value| value == "true")
}

fn mentorship_request_email_subject(request: &MentorshipRequestRecord) -> String {
    format!("GOUP mentorship request from {}", request.requester_label())
}

fn mentorship_request_email_body(request: &MentorshipRequestRecord) -> String {
    format!(
        "\
New GOUP mentorship request

Mentor: {mentor}
Requester: {requester} (@{requester_username})
Requester email: {requester_email}
Request type: {audience}
Listed price: {mentor_price}
Request ID: {request_id}
Total requests received: {request_count}

Message:
{message}
",
        mentor = request.mentor_label(),
        requester = request.requester_label(),
        requester_username = request.requester_username,
        requester_email = request.requester_email,
        audience = request.audience_label(),
        mentor_price = request.mentor_price.as_deref().unwrap_or("Not listed"),
        request_id = request.mentorship_request_id,
        request_count = request.request_count,
        message = request.message.trim(),
    )
}
