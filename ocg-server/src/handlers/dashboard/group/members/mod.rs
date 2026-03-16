//! HTTP handlers for the members section in the group dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{RawQuery, State},
    http::{HeaderName, StatusCode},
    response::{Html, IntoResponse},
};
use garde::Validate;
use serde::{Deserialize, Serialize};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedCommunityId, SelectedGroupId, ValidatedForm},
    },
    router::serde_qs_config,
    services::notifications::{DynNotificationsManager, NewNotification, NotificationKind},
    templates::{
        dashboard::group::members::{self, GroupMembersFilters},
        notifications::GroupCustom,
    },
    types::{
        pagination::{self, NavigationLinks},
        permissions::GroupPermission,
    },
    validation::{MAX_LEN_M, MAX_LEN_NOTIFICATION_BODY, trimmed_non_empty},
};

#[cfg(test)]
mod tests;

// URLs used by the dashboard page and tab partial
const DASHBOARD_URL: &str = "/dashboard/group?tab=members";
const PARTIAL_URL: &str = "/dashboard/group/members";

// Pages handlers.

/// Displays the list of group members.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare list page content
    let (filters, template) = prepare_list_page(
        &db,
        community_id,
        group_id,
        user.user_id,
        raw_query.as_deref().unwrap_or_default(),
    )
    .await?;

    // Prepare response headers
    let url = pagination::build_url(DASHBOARD_URL, &filters)?;
    let headers = [(HeaderName::from_static("hx-push-url"), url)];

    Ok((headers, Html(template.render()?)))
}

// Actions handlers.

/// Sends a custom notification to all group members.
#[instrument(skip_all, err)]
pub(crate) async fn send_group_custom_notification(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    ValidatedForm(notification): ValidatedForm<GroupCustomNotification>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get group data and site settings
    let (site_settings, group, group_members_ids, team_member_ids) = tokio::try_join!(
        db.get_site_settings(),
        db.get_group_summary(community_id, group_id),
        db.list_group_members_ids(group_id),
        db.list_group_team_members_ids(group_id),
    )?;

    // Combine group members and team members
    let mut recipients = group_members_ids;
    recipients.extend(team_member_ids);
    recipients.sort();
    recipients.dedup();

    // If there are no recipients, nothing to do
    if recipients.is_empty() {
        return Ok(StatusCode::NO_CONTENT.into_response());
    }

    // Enqueue notification
    let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);
    let link = format!("{}/{}/group/{}", base_url, group.community_name, group.slug);
    let template_data = GroupCustom {
        body: notification.body.clone(),
        group,
        link,
        theme: site_settings.theme,
        title: notification.title.clone(),
    };
    let new_notification = NewNotification {
        attachments: vec![],
        kind: NotificationKind::GroupCustom,
        recipients,
        template_data: Some(serde_json::to_value(&template_data)?),
    };
    notifications_manager.enqueue(&new_notification).await?;

    // Track custom notification for auditing purposes
    db.track_custom_notification(
        user.user_id,
        None, // event_id is None for group notifications
        Some(group_id),
        &notification.title,
        &notification.body,
    )
    .await?;

    Ok(StatusCode::NO_CONTENT.into_response())
}

// Types.

/// Form data for custom group notifications.
#[derive(Debug, Deserialize, Serialize, Validate)]
pub(crate) struct GroupCustomNotification {
    /// Body text for the notification.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_NOTIFICATION_BODY))]
    pub body: String,
    /// Title line for the notification email.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_M))]
    pub title: String,
}

// Helpers.

/// Prepares the members list page and filters for the group dashboard.
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    community_id: Uuid,
    group_id: Uuid,
    user_id: Uuid,
    raw_query: &str,
) -> Result<(GroupMembersFilters, members::ListPage), HandlerError> {
    // Fetch group members
    let filters: GroupMembersFilters = serde_qs_config().deserialize_str(raw_query)?;
    let (can_manage_members, results) = tokio::try_join!(
        db.user_has_group_permission(&community_id, &group_id, &user_id, GroupPermission::MembersWrite),
        db.list_group_members(group_id, &filters)
    )?;

    // Prepare template
    let navigation_links =
        NavigationLinks::from_filters(&filters, results.total, DASHBOARD_URL, PARTIAL_URL)?;
    let template = members::ListPage {
        can_manage_members,
        members: results.members,
        navigation_links,
        total: results.total,
        limit: filters.limit,
        offset: filters.offset,
    };

    Ok((filters, template))
}
