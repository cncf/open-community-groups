//! HTTP handlers for mentorship requests in the user dashboard.

use askama::Template;
use axum::{
    extract::State,
    response::{Html, IntoResponse},
};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extractors::CurrentUser},
    templates::dashboard::user::mentorship,
};

/// Returns mentorship requests received by the current user.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    let template = prepare_list_page(&db, user.user_id).await?;

    Ok(Html(template.render()?))
}

/// Prepares the mentorship requests list page.
#[instrument(skip(db), err)]
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    user_id: Uuid,
) -> Result<mentorship::ListPage, HandlerError> {
    Ok(db.list_user_mentorship_requests(user_id).await?)
}
