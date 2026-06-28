//! HTTP handlers for the members section in the group dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Path, RawQuery, State},
    http::{HeaderName, StatusCode},
    response::{Html, IntoResponse},
};
use garde::Validate;
use serde::{Deserialize, Serialize};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::{DynDB, notifications::CustomNotificationTracking},
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedAllianceId, SelectedGroupId, ValidatedForm},
    },
    router::serde_qs_config,
    services::notifications::{NewNotification, NotificationKind},
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
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare list page content
    let (filters, template) = prepare_list_page(
        &db,
        alliance_id,
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
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(server_cfg): State<HttpServerConfig>,
    ValidatedForm(notification): ValidatedForm<GroupCustomNotification>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get group data and site settings
    let (site_settings, group, group_members_ids, team_member_ids) = tokio::try_join!(
        db.get_site_settings(),
        db.get_group_summary(alliance_id, group_id),
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

    // Build and enqueue the custom notification with its audit entry
    let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);
    let link = format!(
        "{}/{}/group/{}",
        base_url,
        group.alliance_name,
        group.public_slug()
    );
    let template_data = GroupCustom {
        body: notification.body.clone(),
        group,
        link,
        subject: notification.subject.clone(),
        theme: site_settings.theme,
    };
    let new_notification = NewNotification {
        attachments: vec![],
        kind: NotificationKind::GroupCustom,
        recipients,
        template_data: Some(serde_json::to_value(&template_data)?),
    };
    db.enqueue_tracked_custom_notification(
        &new_notification,
        CustomNotificationTracking {
            body: notification.body.clone(),
            created_by: user.user_id,
            event_id: None,
            group_id: Some(group_id),
            recipient_count: new_notification.recipients.len(),
            subject: notification.subject.clone(),
        },
    )
    .await?;

    Ok(StatusCode::NO_CONTENT.into_response())
}

/// Removes a regular member from the selected group.
#[instrument(skip_all, err)]
pub(crate) async fn delete(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(user_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    db.delete_group_member(user.user_id, group_id, user_id).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

/// Approves a pending group join request.
#[instrument(skip_all, err)]
pub(crate) async fn approve_join_request(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(user_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    db.approve_group_join_request(user.user_id, group_id, user_id).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

/// Rejects a pending group join request.
#[instrument(skip_all, err)]
pub(crate) async fn reject_join_request(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(user_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    db.reject_group_join_request(user.user_id, group_id, user_id).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

/// Blocks a member's `LinkedIn` account from future `LinkedIn` signup/login.
#[instrument(skip_all, err)]
pub(crate) async fn block_linkedin(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(user_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    db.block_group_member_linkedin(user.user_id, group_id, user_id)
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

// Types.

/// Form data for custom group notifications.
#[derive(Debug, Deserialize, Serialize, Validate)]
pub(crate) struct GroupCustomNotification {
    /// Body text for the notification.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_NOTIFICATION_BODY))]
    pub body: String,
    /// Subject line for the notification email.
    #[serde(alias = "title")]
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_M))]
    pub subject: String,
}

// Helpers.

/// Prepares the members list page and filters for the group dashboard.
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    alliance_id: Uuid,
    group_id: Uuid,
    user_id: Uuid,
    raw_query: &str,
) -> Result<(GroupMembersFilters, members::ListPage), HandlerError> {
    // Fetch group members
    let filters: GroupMembersFilters = serde_qs_config().deserialize_str(raw_query)?;
    let (can_manage_members, group, results) = tokio::try_join!(
        db.user_has_group_permission(
            &alliance_id,
            &group_id,
            &user_id,
            GroupPermission::MembersWrite
        ),
        db.get_group_summary(alliance_id, group_id),
        db.list_group_members(group_id, &filters)
    )?;
    let join_requests = if can_manage_members {
        db.list_group_join_requests(group_id).await?
    } else {
        Vec::new()
    };

    // Prepare template
    let navigation_links =
        NavigationLinks::from_filters(&filters, results.total, DASHBOARD_URL, PARTIAL_URL)?;
    let template = members::ListPage {
        can_manage_members,
        default_notification_subject: group.name,
        join_requests,
        members: results.members,
        navigation_links,
        total: results.total,
        limit: filters.limit,
        offset: filters.offset,
        query: filters.query.clone(),
    };

    Ok((filters, template))
}
