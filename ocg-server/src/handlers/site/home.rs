//! HTTP handlers for the global site home page.

use askama::Template;
use axum::{
    extract::State,
    http::Uri,
    response::{Html, IntoResponse},
};
use tracing::{instrument, warn};

use crate::{
    db::DynDB,
    handlers::error::HandlerError,
    router::PUBLIC_SHARED_CACHE_HEADERS,
    templates::{PageId, auth::User, site::home},
    types::{
        event::{EventKind, EventSummary},
        jobs::{JobsFilters, JobsOutput},
        landscape::{LandscapeFilters, LandscapeOutput},
    },
};

#[cfg(test)]
mod tests;

/// Handler that renders the global site home page.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    State(db): State<DynDB>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (
        alliances,
        recently_added_groups,
        site_settings,
        stats,
        upcoming_in_person_events,
        upcoming_virtual_events,
    ) = tokio::try_join!(
        db.list_alliances(),
        db.get_site_recently_added_groups(),
        db.get_site_settings(),
        db.get_site_home_stats(),
        db.get_site_upcoming_events(vec![EventKind::InPerson, EventKind::Hybrid]),
        db.get_site_upcoming_events(vec![EventKind::Virtual, EventKind::Hybrid]),
    )?;
    let latest_feed =
        load_latest_feed(&db, &upcoming_in_person_events, &upcoming_virtual_events).await;
    let template = home::Page {
        alliances,
        latest_feed,
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

async fn load_latest_feed(
    db: &DynDB,
    upcoming_in_person_events: &[EventSummary],
    upcoming_virtual_events: &[EventSummary],
) -> Vec<home::HomeFeedItem> {
    let jobs_filters = JobsFilters {
        limit: Some(2),
        offset: Some(0),
        ..JobsFilters::default()
    };
    let landscape_filters = LandscapeFilters {
        limit: Some(2),
        offset: Some(0),
        ..LandscapeFilters::default()
    };

    let (jobs, landscape, wiki_sections) = tokio::join!(
        db.search_jobs(&jobs_filters),
        db.search_landscape_entries(&landscape_filters),
        load_home_wiki_sections(),
    );
    let jobs = jobs.unwrap_or_else(|error| {
        warn!("home latest feed jobs source failed: {error}");
        JobsOutput::default()
    });
    let landscape = landscape.unwrap_or_else(|error| {
        warn!("home latest feed landscape source failed: {error}");
        LandscapeOutput::default()
    });

    let mut feed = Vec::new();
    feed.extend(
        upcoming_in_person_events
            .iter()
            .chain(upcoming_virtual_events.iter())
            .map(event_feed_item)
            .take(2),
    );
    feed.extend(jobs.jobs.into_iter().take(2).map(|job| home::HomeFeedItem {
        label: "Job".to_string(),
        title: job.title,
        summary: job.summary,
        href: format!("/jobs/{}", job.slug),
        meta: job.company_name,
        hx_boost: true,
    }));
    feed.extend(landscape.entries.into_iter().take(2).map(|entry| {
        home::HomeFeedItem {
            label: "Ecosystem".to_string(),
            title: entry.name,
            summary: entry.summary,
            href: entry
                .website_url
                .or(entry.github_url)
                .unwrap_or_else(|| "/landscape".to_string()),
            meta: entry.category.unwrap_or(entry.kind),
            hx_boost: false,
        }
    }));
    feed.extend(
        wiki_sections
            .iter()
            .flat_map(|section| {
                section.links.iter().take(1).map(|link| home::HomeFeedItem {
                    label: "Reading".to_string(),
                    title: link.title.clone(),
                    summary: section.summary.clone(),
                    href: link.url.clone(),
                    meta: format!("{} · {}", section.title, link.source),
                    hx_boost: false,
                })
            })
            .take(2),
    );

    feed.truncate(8);
    feed
}

fn event_feed_item(event: &EventSummary) -> home::HomeFeedItem {
    home::HomeFeedItem {
        label: "Event".to_string(),
        title: event.name.clone(),
        summary: event
            .description_short
            .clone()
            .unwrap_or_else(|| event.group_name.clone()),
        href: format!(
            "/{}/group/{}/event/{}",
            event.alliance_name,
            event.public_group_slug(),
            event.slug
        ),
        meta: event.starts_at.map_or_else(
            || event.group_name.clone(),
            |date| date.format("%b %d").to_string(),
        ),
        hx_boost: true,
    }
}

#[cfg(not(test))]
async fn load_home_wiki_sections() -> Vec<crate::templates::site::wiki::WikiSection> {
    crate::handlers::site::wiki::load_wiki_sections().await
}

#[cfg(test)]
async fn load_home_wiki_sections() -> Vec<crate::templates::site::wiki::WikiSection> {
    std::future::ready(Vec::new()).await
}
