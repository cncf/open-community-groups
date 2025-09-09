//! HTTP handlers for the group site.

use askama::Template;
use axum::{
    Json,
    extract::{Path, State},
    http::{StatusCode, Uri},
    response::{Html, IntoResponse},
};
use serde_json::json;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    auth::AuthSession,
    config::HttpServerConfig,
    db::DynDB,
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

// Pages handlers.

/// Handler that renders the group home page.
#[instrument(skip_all)]
pub(crate) async fn page(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path(group_slug): Path<String>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let event_kinds = vec![EventKind::InPerson, EventKind::Virtual, EventKind::Hybrid];
    let (community, group, upcoming_events, past_events) = tokio::try_join!(
        db.get_community(community_id),
        db.get_group(community_id, &group_slug),
        db.get_group_upcoming_events(community_id, &group_slug, event_kinds.clone(), 9),
        db.get_group_past_events(community_id, &group_slug, event_kinds, 9)
    )?;
    let template = Page {
        community,
        group,
        page_id: PageId::Group,
        past_events: past_events
            .into_iter()
            .map(|event| group::PastEventCard { event })
            .collect(),
        path: uri.path().to_string(),
        upcoming_events: upcoming_events
            .into_iter()
            .map(|event| group::UpcomingEventCard { event })
            .collect(),
        user: User::default(),
    };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Handler for joining a group.
#[instrument(skip_all)]
pub(crate) async fn join_group(
    auth_session: AuthSession,
    State(cfg): State<HttpServerConfig>,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    CommunityId(community_id): CommunityId,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Join the group
    db.join_group(community_id, group_id, user.user_id).await?;

    // Enqueue welcome to group notification
    let group = db.get_group_summary(group_id).await?;
    let base_url = cfg.base_url.strip_suffix('/').unwrap_or(&cfg.base_url);
    let template_data = GroupWelcome {
        link: format!("{}/group/{}", base_url, group.slug),
        group,
    };
    let notification = NewNotification {
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
    auth_session: AuthSession,
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Leave the group
    db.leave_group(community_id, group_id, user.user_id).await?;

    Ok(StatusCode::NO_CONTENT)
}

/// Handler for checking group membership status.
#[instrument(skip_all)]
pub(crate) async fn membership_status(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Check membership
    let is_member = db.is_group_member(community_id, group_id, user.user_id).await?;

    Ok(Json(json!({
        "is_member": is_member
    })))
}
