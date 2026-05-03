//! HTTP handlers for the group site.

use askama::Template;
use axum::{
    Json,
    extract::{Path, State},
    http::{HeaderMap, StatusCode, Uri},
    response::{Html, IntoResponse},
};
use chrono::Duration;
use serde_json::json;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    activity_tracker::{Activity, DynActivityTracker},
    config::HttpServerConfig,
    db::DynDB,
    handlers::{extractors::CurrentUser, prepare_headers, request_matches_site, trim_public_gallery_images},
    services::notifications::{DynNotificationsManager, NewNotification, NotificationKind},
    templates::{
        PageId,
        auth::User,
        group::{self, Page},
        notifications::GroupWelcome,
    },
    types::event::EventKind,
};

use super::{error::HandlerError, extractors::CommunityId};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Handler that renders the group home page.
#[instrument(skip_all)]
pub(crate) async fn page(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path((_, group_slug)): Path<(String, String)>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Fetch the group page data
    let event_kinds = vec![EventKind::InPerson, EventKind::Virtual, EventKind::Hybrid];
    let (group, past_events, site_settings, upcoming_events) = tokio::try_join!(
        db.get_group_full_by_slug(community_id, &group_slug),
        db.get_group_past_events(community_id, &group_slug, event_kinds.clone(), 9),
        db.get_site_settings(),
        db.get_group_upcoming_events(community_id, &group_slug, event_kinds, 9)
    )?;
    let mut group = group.ok_or(HandlerError::NotFound)?;

    // Trim gallery media
    trim_public_gallery_images(&mut group.photos_urls);

    // Only display featured sponsors on the group page
    group.sponsors.retain(|sponsor| sponsor.featured);

    // Prepare the page template
    let template = Page {
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

    // Prepare response headers
    let headers = prepare_headers(Duration::hours(1), &[])?;

    Ok((headers, Html(template.render()?)))
}

// Actions handlers.

/// Handler for joining a group.
#[instrument(skip_all)]
pub(crate) async fn join_group(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    CommunityId(community_id): CommunityId,
    Path((_, group_id)): Path<(String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Join the group
    db.join_group(community_id, group_id, user.user_id).await?;

    // Enqueue welcome to group notification
    let (site_settings, group) = tokio::try_join!(
        db.get_site_settings(),
        db.get_group_summary(community_id, group_id)
    )?;
    let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);
    let template_data = GroupWelcome {
        link: format!("{}/{}/group/{}", base_url, group.community_name, group.slug),
        group,
        theme: site_settings.theme,
    };
    let notification = NewNotification {
        attachments: vec![],
        kind: NotificationKind::GroupWelcome,
        recipients: vec![user.user_id],
        template_data: Some(serde_json::to_value(&template_data)?),
    };
    notifications_manager.enqueue(&notification).await?;

    Ok(StatusCode::NO_CONTENT)
}

/// Handler for leaving a group.
#[instrument(skip_all)]
pub(crate) async fn leave_group(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path((_, group_id)): Path<(String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Leave the group
    db.leave_group(community_id, group_id, user.user_id).await?;

    Ok(StatusCode::NO_CONTENT)
}

/// Handler for checking group membership status.
#[instrument(skip_all)]
pub(crate) async fn membership_status(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path((_, group_id)): Path<(String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Check membership
    let is_member = db.is_group_member(community_id, group_id, user.user_id).await?;

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
