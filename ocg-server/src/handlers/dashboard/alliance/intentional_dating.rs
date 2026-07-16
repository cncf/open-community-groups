//! HTTP handlers for alliance intentional dating curation.

use askama::Template;
use axum::{
    extract::State,
    http::StatusCode,
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedAllianceId, ValidatedForm},
    },
    templates::dashboard::alliance::intentional_dating::{self, IntroForm},
};

/// Displays private alliance intentional dating opt-ins.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    let opt_ins = db.list_intentional_dating_opt_ins(alliance_id, None).await?;
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
    State(db): State<DynDB>,
    ValidatedForm(input): ValidatedForm<IntroForm>,
) -> Result<impl IntoResponse, HandlerError> {
    db.add_intentional_dating_intro(
        user.user_id,
        alliance_id,
        input.group_id,
        input.first_user_id,
        input.second_user_id,
        input.admin_notes,
    )
    .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-alliance-dashboard-table")],
    ))
}
