//! HTTP handlers for group intentional dating curation.

use askama::Template;
use axum::{
    extract::State,
    http::StatusCode,
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    config::HttpServerConfig,
    db::DynDB,
    handlers::{
        dashboard::common::enqueue_intentional_dating_intro_notifications,
        error::HandlerError,
        extractors::{CurrentUser, SelectedAllianceId, SelectedGroupId, ValidatedForm},
    },
    services::notifications::DynNotificationsManager,
    templates::dashboard::group::intentional_dating::{self, IntroForm},
};

/// Displays private group intentional dating opt-ins.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    let opt_ins = db
        .list_intentional_dating_opt_ins(alliance_id, Some(group_id))
        .await?;
    let template = intentional_dating::ListPage {
        can_manage_introductions: true,
        opt_ins,
    };

    Ok(Html(template.render()?))
}

/// Records an admin-curated intentional dating introduction.
#[instrument(skip_all, err)]
pub(crate) async fn add_intro(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    ValidatedForm(input): ValidatedForm<IntroForm>,
) -> Result<impl IntoResponse, HandlerError> {
    db.add_intentional_dating_intro(
        user.user_id,
        alliance_id,
        group_id,
        input.first_user_id,
        input.second_user_id,
        input.admin_notes.clone(),
    )
    .await?;
    enqueue_intentional_dating_intro_notifications(
        &db,
        &notifications_manager,
        &server_cfg,
        alliance_id,
        group_id,
        input.first_user_id,
        input.second_user_id,
        input.notification_message.as_deref(),
    )
    .await;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}
