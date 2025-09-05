//! HTTP handlers for the attendees section in the group dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::State,
    response::{Html, IntoResponse},
};
use axum_extra::extract::Query as QsQuery;
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
    QsQuery(filters): QsQuery<attendees::AttendeesFilters>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (filters_options, attendees) = tokio::try_join!(
        db.get_attendees_filters_options(group_id),
        db.search_event_attendees(group_id, &filters)
    )?;
    let template = attendees::ListPage {
        attendees,
        filters,
        filters_options,
    };

    Ok(Html(template.render()?))
}
