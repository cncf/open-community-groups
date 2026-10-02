//! HTTP handlers for the user dashboard notifications tab.

use askama::Template;
use axum::{
    Json,
    extract::{Path, State},
    http::{HeaderName, StatusCode},
    response::{Html, IntoResponse},
};
use axum_messages::Messages;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    auth,
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, ValidatedFormQs},
    },
    templates::dashboard::user::notifications::{MutedGroupsList, Page},
    types::dashboard::user::notifications::NotificationPreferencesInput,
};

#[cfg(test)]
mod tests;

/// URL used by the full dashboard page.
const DASHBOARD_URL: &str = "/dashboard/user?tab=notifications";

// Pages handlers.

/// Returns the connected groups the user can mute.
#[instrument(skip_all)]
pub(crate) async fn group_options(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load the groups available to mute
    let options = db.list_user_notification_group_options(user.user_id).await?;

    Ok(Json(options))
}

/// Returns the muted groups list content.
#[instrument(skip_all)]
pub(crate) async fn muted_groups(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Render the current muted groups
    let preferences = db.get_user_notification_preferences(user.user_id).await?;
    let template = MutedGroupsList {
        muted_groups: preferences.muted_groups,
    };

    Ok(Html(template.render()?))
}

/// Returns the notifications page for the user dashboard.
#[instrument(skip_all)]
pub(crate) async fn page(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare page content
    let template = prepare_page(&db, &user).await?;

    // Prepare response headers
    let headers = [(HeaderName::from_static("hx-push-url"), DASHBOARD_URL)];

    Ok((headers, Html(template.render()?)))
}

// Actions handlers.

/// Mutes optional notifications from a connected group.
#[instrument(skip_all)]
pub(crate) async fn mute_group(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Mute the group
    db.mute_user_group_notifications(user.user_id, group_id).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-muted-groups")],
    ))
}

/// Unmutes optional notifications from a group.
#[instrument(skip_all)]
pub(crate) async fn unmute_group(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Unmute the group
    db.unmute_user_group_notifications(user.user_id, group_id).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-muted-groups")],
    ))
}

/// Updates the submitted notification category preferences.
#[instrument(skip_all)]
pub(crate) async fn update_preferences(
    CurrentUser(user): CurrentUser,
    messages: Messages,
    State(db): State<DynDB>,
    ValidatedFormQs(input): ValidatedFormQs<NotificationPreferencesInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Save the submitted categories
    db.update_user_notification_preferences(user.user_id, &input).await?;
    messages.success("Notification preferences updated.");

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}

// Helpers.

/// Prepares the notifications page for the user.
pub(crate) async fn prepare_page(db: &DynDB, user: &auth::User) -> Result<Page, HandlerError> {
    // Load the current preferences
    let preferences = db.get_user_notification_preferences(user.user_id).await?;

    Ok(Page {
        preferences,
        show_community_team_section: user.belongs_to_community_team.unwrap_or(false),
        show_group_team_section: user.belongs_to_any_group_team.unwrap_or(false),
    })
}
