//! HTTP handlers for the group site.

use askama::Template;
use axum::{
    Json,
    extract::{Path, State},
    http::{HeaderMap, StatusCode, Uri},
    response::{Html, IntoResponse, Redirect},
};
use serde_json::json;
use tracing::{instrument, warn};
use uuid::Uuid;

use crate::{
    activity_tracker::{Activity, DynActivityTracker},
    auth::AuthSession,
    config::HttpServerConfig,
    db::DynDB,
    handlers::{
        extractors::CurrentUser, request_matches_site, site::not_found, trim_public_gallery_images,
    },
    router::PUBLIC_SHARED_CACHE_HEADERS,
    services::notifications::{DynNotificationsManager, NewNotification, NotificationKind},
    templates::{
        PageId,
        auth::User,
        group::{self, Page, SpotlightsPage, StorePage},
        notifications::GroupWelcome,
    },
    types::{event::EventKind, group::GroupFull},
};

use super::{error::HandlerError, extractors::AllianceId};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Handler that renders the group home page.
#[instrument(skip_all)]
pub(crate) async fn page(
    State(db): State<DynDB>,
    State(server_cfg): State<HttpServerConfig>,
    Path((alliance_name, group_slug)): Path<(String, String)>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Get alliance and site settings
    let (alliance_id, site_settings) = tokio::try_join!(
        db.get_alliance_id_by_name(&alliance_name),
        db.get_site_settings()
    )?;
    let Some(alliance_id) = alliance_id else {
        return not_found::render(site_settings);
    };

    // Fetch the group page data
    let event_kinds = vec![EventKind::InPerson, EventKind::Virtual, EventKind::Hybrid];
    let (group, past_events, upcoming_events) = tokio::try_join!(
        db.get_group_full_by_slug(alliance_id, &group_slug),
        db.get_group_past_events(alliance_id, &group_slug, event_kinds.clone(), 9),
        db.get_group_upcoming_events(alliance_id, &group_slug, event_kinds, 9)
    )?;
    let Some(mut group) = group else {
        return not_found::render(site_settings);
    };

    // Redirect generated group slugs to their pretty URL
    if should_redirect_to_pretty_group_slug(&group, &group_slug) {
        let url = public_group_url(&alliance_name, group.public_slug(), &uri);
        return Ok(Redirect::temporary(&url).into_response());
    }

    // Trim gallery media
    trim_public_gallery_images(&mut group.photos_urls);

    // Only display featured sponsors on the group page
    group.sponsors.retain(|sponsor| sponsor.featured);

    // Prepare the page template
    let template = Page {
        base_url: server_cfg.base_url,
        group,
        page_id: PageId::Group,
        past_events: past_events
            .into_iter()
            .map(|event| group::PastEventCard { event })
            .collect(),
        path: uri.path().to_string(),
        site_settings,
        upcoming_events: upcoming_events
            .into_iter()
            .map(|event| group::UpcomingEventCard { event })
            .collect(),
        user: User::default(),
    };

    Ok((PUBLIC_SHARED_CACHE_HEADERS, Html(template.render()?)).into_response())
}

/// Handler that renders logged-in group member spotlights.
#[instrument(skip_all)]
pub(crate) async fn spotlights_page(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    State(server_cfg): State<HttpServerConfig>,
    Path((alliance_name, group_slug)): Path<(String, String)>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    let (alliance_id, site_settings) = tokio::try_join!(
        db.get_alliance_id_by_name(&alliance_name),
        db.get_site_settings()
    )?;
    let Some(alliance_id) = alliance_id else {
        return not_found::render(site_settings);
    };

    let Some(mut group) = db.get_group_full_by_slug(alliance_id, &group_slug).await? else {
        return not_found::render(site_settings);
    };
    trim_public_gallery_images(&mut group.photos_urls);
    group.sponsors.clear();

    let spotlights = db.list_group_member_spotlights(group.group_id, false).await?;
    let template = SpotlightsPage {
        base_url: server_cfg.base_url,
        group,
        page_id: PageId::Group,
        path: uri.path().to_string(),
        site_settings,
        spotlights,
        user: User::from_session(auth_session).await?,
    };

    Ok(Html(template.render()?).into_response())
}

/// Handler that renders the public group store page.
#[instrument(skip_all)]
pub(crate) async fn store_page(
    State(db): State<DynDB>,
    State(server_cfg): State<HttpServerConfig>,
    Path((alliance_name, group_slug)): Path<(String, String)>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    let (alliance_id, site_settings) = tokio::try_join!(
        db.get_alliance_id_by_name(&alliance_name),
        db.get_site_settings()
    )?;
    let Some(alliance_id) = alliance_id else {
        return not_found::render(site_settings);
    };

    let Some(mut group) = db.get_group_full_by_slug(alliance_id, &group_slug).await? else {
        return not_found::render(site_settings);
    };
    trim_public_gallery_images(&mut group.photos_urls);
    group.sponsors.retain(|sponsor| sponsor.featured);

    let store_items = db.list_group_store_items(group.group_id, false).await?;
    let template = StorePage {
        base_url: server_cfg.base_url,
        group,
        page_id: PageId::Group,
        path: uri.path().to_string(),
        site_settings,
        store_items,
        user: User::default(),
    };

    Ok((PUBLIC_SHARED_CACHE_HEADERS, Html(template.render()?)).into_response())
}

// Helpers.

/// Builds a public group URL with the original query string, if present.
fn public_group_url(alliance_name: &str, group_slug: &str, uri: &Uri) -> String {
    let mut url = format!("/{alliance_name}/group/{group_slug}");
    if let Some(query) = uri.query() {
        url.push('?');
        url.push_str(query);
    }

    url
}

/// Returns whether a public group request should redirect to a pretty group slug.
fn should_redirect_to_pretty_group_slug(group: &GroupFull, group_slug: &str) -> bool {
    group.slug_pretty.is_some() && group_slug == group.slug
}

// Actions handlers.

/// Handler for joining a group.
#[instrument(skip_all)]
pub(crate) async fn join_group(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    AllianceId(alliance_id): AllianceId,
    Path((_, group_id)): Path<(String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Join the group
    db.join_group(alliance_id, group_id, user.user_id).await?;

    // Enqueue welcome notification best-effort after the membership mutation
    if let Err(err) = async {
        let (site_settings, group) = tokio::try_join!(
            db.get_site_settings(),
            db.get_group_summary(alliance_id, group_id)
        )?;
        let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);
        let template_data = GroupWelcome {
            link: format!(
                "{}/{}/group/{}",
                base_url,
                group.alliance_name,
                group.public_slug()
            ),
            group,
            theme: site_settings.theme,
        };
        let notification = NewNotification {
            attachments: vec![],
            kind: NotificationKind::GroupWelcome,
            recipients: vec![user.user_id],
            template_data: Some(serde_json::to_value(&template_data)?),
        };
        notifications_manager.enqueue(&notification).await
    }
    .await
    {
        warn!(
            error = %err,
            %alliance_id,
            %group_id,
            user_id = %user.user_id,
            "failed to enqueue group welcome notification"
        );
    }

    Ok(StatusCode::NO_CONTENT)
}

/// Handler for leaving a group.
#[instrument(skip_all)]
pub(crate) async fn leave_group(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    AllianceId(alliance_id): AllianceId,
    Path((_, group_id)): Path<(String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Leave the group
    db.leave_group(alliance_id, group_id, user.user_id).await?;

    Ok(StatusCode::NO_CONTENT)
}

/// Handler for checking group membership status.
#[instrument(skip_all)]
pub(crate) async fn membership_status(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    AllianceId(alliance_id): AllianceId,
    Path((_, group_id)): Path<(String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Check membership
    let is_member = db.is_group_member(alliance_id, group_id, user.user_id).await?;

    Ok(Json(json!({
        "is_member": is_member
    })))
}

/// Tracks a group page view.
#[instrument(skip_all)]
pub(crate) async fn track_view(
    headers: HeaderMap,
    State(activity_tracker): State<DynActivityTracker>,
    State(server_cfg): State<HttpServerConfig>,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    if request_matches_site(&server_cfg, &headers)? {
        activity_tracker.track(Activity::GroupView { group_id }).await?;
    }

    Ok(StatusCode::NO_CONTENT)
}
