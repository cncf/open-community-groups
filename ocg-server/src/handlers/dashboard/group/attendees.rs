//! HTTP handlers for the attendees section in the group dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Query, State},
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extractors::SelectedGroupId},
    templates::dashboard::group::attendees,
};

// Pages handlers.

/// Displays the list of attendees for the selected event and filters.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Query(filters): Query<attendees::AttendeesFilters>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let attendees = db.search_event_attendees(group_id, &filters).await?;
    let event = if let Some(event_id) = filters.event_id {
        Some(db.get_event_summary(event_id).await?)
    } else {
        None
    };
    let template = attendees::ListPage {
        attendees,
        group_id,
        event,
    };

    Ok(Html(template.render()?))
}
