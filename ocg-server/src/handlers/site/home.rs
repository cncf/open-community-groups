//! HTTP handlers for the global site home page.

use askama::Template;
use axum::{
    extract::State,
    http::Uri,
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    db::DynDB,
    handlers::error::HandlerError,
    router::PUBLIC_SHARED_CACHE_HEADERS,
    templates::{PageId, auth::User, site::home},
    types::event::EventKind,
};

#[cfg(test)]
mod tests;

/// Handler that renders the global site home page.
#[instrument(skip_all, err)]
pub(crate) async fn page(State(db): State<DynDB>, uri: Uri) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (
        communities,
        recently_added_groups,
        site_settings,
        stats,
        upcoming_in_person_events,
        upcoming_virtual_events,
    ) = tokio::try_join!(
        db.list_communities(),
        db.get_site_recently_added_groups(),
        db.get_site_settings(),
        db.get_site_home_stats(),
        db.get_site_upcoming_events(vec![EventKind::InPerson, EventKind::Hybrid]),
        db.get_site_upcoming_events(vec![EventKind::Virtual, EventKind::Hybrid]),
    )?;
    let template = home::Page {
        communities,
        page_id: PageId::SiteHome,
        path: uri.path().to_string(),
        recently_added_groups: recently_added_groups
            .into_iter()
            .map(|group| home::GroupCard { group })
            .collect(),
        site_settings,
        stats,
        upcoming_in_person_events: upcoming_in_person_events
            .into_iter()
            .map(|event| home::EventCard { event })
            .collect(),
        upcoming_virtual_events: upcoming_virtual_events
            .into_iter()
            .map(|event| home::EventCard { event })
            .collect(),
        user: User::default(),
    };

    Ok((PUBLIC_SHARED_CACHE_HEADERS, Html(template.render()?)))
}
