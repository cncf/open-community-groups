//! HTTP handlers for the event analytics tab in the group dashboard.

use askama::Template;
use axum::{
    extract::{Path, State},
    response::{Html, IntoResponse},
};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extractors::SelectedGroupId},
    templates::dashboard::group::event_analytics,
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Displays the analytics of an event owned by the selected group.
#[instrument(skip_all)]
pub(crate) async fn page(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Check the event is still owned by the group, bypassing the stats cache
    if !db.group_has_event(group_id, event_id).await? {
        return Err(HandlerError::NotFound);
    }

    // Load the cached event statistics
    let Some(stats) = db.get_event_analytics(group_id, event_id).await? else {
        return Err(HandlerError::NotFound);
    };

    // Render the analytics partial
    let template = event_analytics::Page { event_id, stats };

    Ok(Html(template.render()?))
}
