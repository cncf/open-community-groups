//! HTTP handlers for the attendees section in the group dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Path, RawQuery, State},
    http::{StatusCode, header::CONTENT_TYPE},
    response::{Html, IntoResponse},
};
use chrono::Duration;
use garde::Validate;
use qrcode::render::svg;
use serde::{Deserialize, Serialize};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedCommunityId, SelectedGroupId, ValidatedForm},
        prepare_headers,
    },
    router::serde_qs_config,
    services::notifications::{DynNotificationsManager, NewNotification, NotificationKind},
    templates::{
        dashboard::group::attendees::{self, AttendeesFilters, AttendeesPaginationFilters},
        notifications::EventCustom,
    },
    types::{pagination::NavigationLinks, permissions::GroupPermission},
    validation::{MAX_LEN_M, MAX_LEN_NOTIFICATION_BODY, trimmed_non_empty},
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Displays the list of attendees for a specific event.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Fetch event summary and attendees
    let page_filters: AttendeesPaginationFilters =
        serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
    let search_filters = AttendeesFilters {
        event_id,
        limit: page_filters.limit,
        offset: page_filters.offset,
    };
    let (can_manage_events, event, search_attendees_results) = tokio::try_join!(
        db.user_has_group_permission(
            &community_id,
            &group_id,
            &user.user_id,
            GroupPermission::EventsWrite
        ),
        db.get_event_summary(community_id, group_id, event_id),
        db.search_event_attendees(group_id, &search_filters)
    )?;

    // Prepare template
    let navigation_links = NavigationLinks::from_filters(
        &page_filters,
        search_attendees_results.total,
        &format!("/dashboard/group/events/{event_id}/attendees"),
        &format!("/dashboard/group/events/{event_id}/attendees"),
    )?;
    let template = attendees::ListPage {
        attendees: search_attendees_results.attendees,
        can_manage_events,
        event,
        navigation_links,
        total: search_attendees_results.total,
        limit: page_filters.limit,
        offset: page_filters.offset,
    };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Generates a QR code for event check-in.
#[instrument(skip_all, err)]
pub(crate) async fn generate_check_in_qr_code(
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(server_cfg): State<HttpServerConfig>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get community name (cached) and ensure event belongs to selected group
    let (community_name, _) = tokio::try_join!(
        db.get_community_name_by_id(community_id),
        db.get_event_summary(community_id, group_id, event_id)
    )?;
    let Some(community_name) = community_name else {
        return Err(anyhow::anyhow!("community not found").into());
    };

    // Get base URL from configuration
    let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);

    // Construct check-in URL
    let check_in_url = format!("{base_url}/{community_name}/check-in/{event_id}");

    // Generate QR code
    let code = qrcode::QrCode::new(check_in_url.as_bytes())
        .map_err(|e| anyhow::anyhow!("Failed to generate QR code: {e}"))?;
    let svg = code
        .render()
        .min_dimensions(500, 500)
        .dark_color(svg::Color("#000000"))
        .light_color(svg::Color("#ffffff"))
        .build();

    // Prepare response headers
    let headers = prepare_headers(Duration::hours(1), &[(CONTENT_TYPE.as_str(), "image/svg+xml")])?;

    // Return SVG response
    Ok((StatusCode::OK, headers, svg))
}

/// Manually checks in a user for an event, bypassing the check-in window validation.
#[instrument(skip_all, err)]
pub(crate) async fn manual_check_in(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path((event_id, user_id)): Path<(Uuid, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Validate event belongs to the selected group
    db.get_event_summary(community_id, group_id, event_id).await?;

    // Check-in with dashboard-specific auditing
    db.manual_check_in_event(user.user_id, community_id, event_id, user_id)
        .await?;

    Ok(StatusCode::NO_CONTENT)
}

/// Sends a custom notification to event attendees.
#[instrument(skip_all, err)]
#[allow(clippy::too_many_arguments)]
pub(crate) async fn send_event_custom_notification(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    Path(event_id): Path<Uuid>,
    ValidatedForm(notification): ValidatedForm<EventCustomNotification>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get event data and site settings
    let (site_settings, event, event_attendees_ids) = tokio::try_join!(
        db.get_site_settings(),
        db.get_event_summary_by_id(community_id, event_id),
        db.list_event_attendees_ids(group_id, event_id),
    )?;

    // If there are no attendees, nothing to do
    if event_attendees_ids.is_empty() {
        return Ok(StatusCode::NO_CONTENT.into_response());
    }

    // Enqueue notification
    let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);
    let link = format!(
        "{}/{}/group/{}/event/{}",
        base_url, event.community_name, event.group_slug, event.slug
    );
    let template_data = EventCustom {
        body: notification.body.clone(),
        event,
        link,
        theme: site_settings.theme,
        title: notification.title.clone(),
    };
    let new_notification = NewNotification {
        attachments: vec![],
        kind: NotificationKind::EventCustom,
        recipients: event_attendees_ids,
        template_data: Some(serde_json::to_value(&template_data)?),
    };
    notifications_manager.enqueue(&new_notification).await?;

    // Track custom notification for auditing purposes
    db.track_custom_notification(
        user.user_id,
        Some(event_id),
        Some(group_id),
        new_notification.recipients.len(),
        &notification.title,
        &notification.body,
    )
    .await?;

    Ok(StatusCode::NO_CONTENT.into_response())
}

// Types.

/// Form data for custom event notifications.
#[derive(Debug, Deserialize, Serialize, Validate)]
pub(crate) struct EventCustomNotification {
    /// Body text for the notification.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_NOTIFICATION_BODY))]
    pub body: String,
    /// Title line for the notification email.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_M))]
    pub title: String,
}
