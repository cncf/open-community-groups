//! HTTP handlers for alliance book exchange.

use askama::Template;
use axum::{
    extract::State,
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extractors::SelectedAllianceId},
    templates::dashboard::alliance::book_exchange,
};

/// Displays private alliance book exchange member lists.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    let members = db.list_book_exchange_members(alliance_id, None).await?;
    let template = book_exchange::ListPage {
        can_manage_book_exchange: true,
        members,
    };

    Ok(Html(template.render()?))
}
