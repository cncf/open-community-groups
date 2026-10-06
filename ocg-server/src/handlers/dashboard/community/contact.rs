//! HTTP handlers for the contact section of the community dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::State,
    http::StatusCode,
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
        extractors::{CurrentUser, SelectedCommunityId, ValidatedFormQs, ValidatedQuery},
    },
    services::notifications::enqueue::enqueue_tracked_community_custom_notification,
    templates::dashboard::community::contact,
    types::{
        dashboard::community::contact::CommunityContactFilters,
        notifications::{CommunityCustomNotificationInput, CustomNotificationContent},
        permissions::CommunityPermission,
    },
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Displays the contact page used to email group team members.
#[instrument(skip_all)]
pub(crate) async fn page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let community = db.get_community_summary(community_id).await?;
    let template = prepare_page(&db, community_id, user.user_id, community.display_name).await?;

    Ok(Html(template.render()?))
}

/// Displays the summary of the group team members matching the filters.
#[instrument(skip_all)]
pub(crate) async fn recipients(
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
    ValidatedQuery(query): ValidatedQuery<CommunityContactRecipientsQuery>,
) -> Result<impl IntoResponse, HandlerError> {
    // Summarize the recipients matching the filters
    let summary = db
        .get_community_contact_recipients_summary(community_id, &query.filters)
        .await?;

    // Prepare template
    let template = contact::RecipientsSummary {
        filters_key: query.filters.to_canonical_query(),
        summary,
    };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Sends a custom notification to the group team members matching the filters.
#[instrument(skip_all)]
pub(crate) async fn send_community_custom_notification(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
    State(server_cfg): State<HttpServerConfig>,
    ValidatedFormQs(notification): ValidatedFormQs<CommunityCustomNotification>,
) -> Result<impl IntoResponse, HandlerError> {
    // Resolve recipients, enqueue and audit the notification atomically
    enqueue_tracked_community_custom_notification(
        db.as_ref(),
        &server_cfg,
        &CommunityCustomNotificationInput {
            actor_user_id: user.user_id,
            community_id,
            content: notification.content,
            filters: notification.filters,
        },
    )
    .await?;

    Ok(StatusCode::NO_CONTENT)
}

// Types.

/// Form data for community custom notifications.
#[derive(Debug, Deserialize, Serialize, Validate)]
pub(crate) struct CommunityCustomNotification {
    /// Subject and body of the notification.
    #[serde(flatten)]
    #[garde(dive)]
    pub content: CustomNotificationContent,

    /// Filters selecting the group team members to notify.
    #[serde(default)]
    #[garde(dive)]
    pub filters: CommunityContactFilters,
}

/// Query parameters for the recipients summary.
#[derive(Debug, Default, Deserialize, Serialize, Validate)]
pub(crate) struct CommunityContactRecipientsQuery {
    /// Filters selecting the group team members to summarize.
    #[serde(default)]
    #[garde(dive)]
    pub filters: CommunityContactFilters,
}

// Helpers.

/// Prepares the contact page for the community dashboard.
pub(crate) async fn prepare_page(
    db: &DynDB,
    community_id: Uuid,
    user_id: Uuid,
    default_subject: String,
) -> Result<contact::Page, HandlerError> {
    // Load permissions, filter options and the summary of the default filters
    let filters = CommunityContactFilters::default();
    let (can_send, filter_options, roles, summary) = tokio::try_join!(
        db.user_has_community_permission(&community_id, &user_id, CommunityPermission::GroupsWrite),
        db.list_community_contact_filter_options(community_id),
        db.list_group_roles(),
        db.get_community_contact_recipients_summary(community_id, &filters),
    )?;

    // Prepare template
    let template = contact::Page {
        can_send,
        default_notification_subject: default_subject,
        filter_options,
        filters_key: filters.to_canonical_query(),
        roles,
        summary,
    };

    Ok(template)
}
