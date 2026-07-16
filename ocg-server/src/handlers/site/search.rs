//! HTTP handlers for the public site search page.

use std::collections::HashMap;

use askama::Template;
use axum::{
    extract::{Query, State},
    http::Uri,
    response::{Html, IntoResponse},
};
use percent_encoding::{NON_ALPHANUMERIC, utf8_percent_encode};
use tracing::{instrument, warn};

use crate::{
    db::DynDB,
    db::common::{SearchEventsOutput, SearchGroupsOutput},
    handlers::error::HandlerError,
    router::PUBLIC_SHARED_CACHE_HEADERS,
    templates::{
        PageId,
        auth::User,
        site::{
            search::{self, SearchResult, SearchSection},
            wiki::WikiSection,
        },
    },
    types::{
        jobs::{JobsFilters, JobsOutput},
        landscape::{LandscapeFilters, LandscapeOutput},
        search::{SearchEventsFilters, SearchGroupsFilters},
    },
};

const SEARCH_LIMIT: usize = 4;

#[cfg(test)]
mod tests;

/// Handler that renders the public search page.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    State(db): State<DynDB>,
    Query(query): Query<HashMap<String, String>>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    let search_query = query
        .get("query")
        .map(|value| value.trim().to_string())
        .unwrap_or_default();
    let encoded_query = utf8_percent_encode(&search_query, NON_ALPHANUMERIC).to_string();
    let sections = if search_query.is_empty() {
        Vec::new()
    } else {
        search_all(&db, &search_query, &encoded_query).await
    };
    let total = sections.iter().map(|section| section.total).sum();

    let template = search::Page {
        page_id: PageId::SiteSearch,
        path: uri.path().to_string(),
        site_settings: db.get_site_settings().await?,
        user: User::default(),
        query: search_query,
        encoded_query,
        sections,
        total,
    };

    Ok((PUBLIC_SHARED_CACHE_HEADERS, Html(template.render()?)))
}

#[allow(clippy::too_many_lines)]
async fn search_all(db: &DynDB, query: &str, encoded_query: &str) -> Vec<SearchSection> {
    let events_filters = SearchEventsFilters {
        alliance: vec!["goup".to_string()],
        ts_query: Some(query.to_string()),
        limit: Some(SEARCH_LIMIT),
        offset: Some(0),
        ..SearchEventsFilters::default()
    };
    let groups_filters = SearchGroupsFilters {
        alliance: vec!["goup".to_string()],
        ts_query: Some(query.to_string()),
        limit: Some(SEARCH_LIMIT),
        offset: Some(0),
        ..SearchGroupsFilters::default()
    };
    let jobs_filters = JobsFilters {
        query: Some(query.to_string()),
        limit: Some(SEARCH_LIMIT),
        offset: Some(0),
        ..JobsFilters::default()
    };
    let landscape_filters = LandscapeFilters {
        query: Some(query.to_string()),
        limit: Some(SEARCH_LIMIT),
        offset: Some(0),
        ..LandscapeFilters::default()
    };

    let (events, groups, jobs, landscape, wiki_sections) = tokio::join!(
        db.search_events(&events_filters),
        db.search_groups(&groups_filters),
        db.search_jobs(&jobs_filters),
        db.search_landscape_entries(&landscape_filters),
        crate::handlers::site::wiki::load_wiki_sections(),
    );
    let events = events.unwrap_or_else(|error| {
        warn!("site search events source failed: {error}");
        SearchEventsOutput::default()
    });
    let groups = groups.unwrap_or_else(|error| {
        warn!("site search groups source failed: {error}");
        SearchGroupsOutput::default()
    });
    let jobs = jobs.unwrap_or_else(|error| {
        warn!("site search jobs source failed: {error}");
        JobsOutput::default()
    });
    let landscape = landscape.unwrap_or_else(|error| {
        warn!("site search landscape source failed: {error}");
        LandscapeOutput::default()
    });

    let mut sections = Vec::new();
    sections.push(SearchSection {
        title: "Events".to_string(),
        href: format!("/explore?alliance[0]=goup&entity=events&ts_query={encoded_query}"),
        total: events.total,
        results: events
            .events
            .into_iter()
            .map(|event| {
                let href = format!(
                    "/{}/group/{}/event/{}",
                    event.alliance_name,
                    event.public_group_slug(),
                    event.slug
                );
                let summary = event
                    .description_short
                    .clone()
                    .or_else(|| event.starts_at.map(|date| date.format("%b %d, %Y").to_string()))
                    .unwrap_or_else(|| event.group_name.clone());
                SearchResult {
                    title: event.name,
                    href,
                    summary,
                    eyebrow: format!("{} · {}", event.group_name, event.group_category_name),
                    hx_boost: true,
                }
            })
            .collect(),
    });
    sections.push(SearchSection {
        title: "Groups".to_string(),
        href: format!("/explore?alliance[0]=goup&entity=groups&ts_query={encoded_query}"),
        total: groups.total,
        results: groups
            .groups
            .into_iter()
            .map(|group| {
                let href = format!("/{}/group/{}", group.alliance_name, group.public_slug());
                let summary = group
                    .description_short
                    .clone()
                    .or_else(|| group.location(80))
                    .unwrap_or_else(|| group.category.name.clone());
                SearchResult {
                    title: group.name,
                    href,
                    summary,
                    eyebrow: group.alliance_display_name,
                    hx_boost: true,
                }
            })
            .collect(),
    });
    sections.push(SearchSection {
        title: "Jobs".to_string(),
        href: format!("/jobs?query={encoded_query}"),
        total: jobs.total,
        results: jobs
            .jobs
            .into_iter()
            .map(|job| SearchResult {
                title: job.title,
                href: format!("/jobs/{}", job.slug),
                summary: job.summary,
                eyebrow: job.company_name,
                hx_boost: true,
            })
            .collect(),
    });
    sections.push(SearchSection {
        title: "Ecosystem".to_string(),
        href: format!("/landscape?query={encoded_query}"),
        total: landscape.total,
        results: landscape
            .entries
            .into_iter()
            .map(|entry| SearchResult {
                title: entry.name,
                href: entry
                    .website_url
                    .or(entry.github_url)
                    .unwrap_or_else(|| format!("/landscape?query={encoded_query}")),
                summary: entry.summary,
                eyebrow: entry.category.unwrap_or(entry.kind),
                hx_boost: false,
            })
            .collect(),
    });
    sections.push(search_wiki(query, &wiki_sections));

    sections
}

fn search_wiki(query: &str, wiki_sections: &[WikiSection]) -> SearchSection {
    let terms = query.split_whitespace().map(str::to_lowercase).collect::<Vec<_>>();
    let mut results = Vec::new();

    for section in wiki_sections {
        for link in &section.links {
            let haystack =
                format!("{} {} {}", link.title, link.source, section.title).to_lowercase();
            if terms.iter().all(|term| haystack.contains(term)) {
                results.push(SearchResult {
                    title: link.title.clone(),
                    href: link.url.clone(),
                    summary: section.summary.clone(),
                    eyebrow: format!("{} · {}", section.title, link.source),
                    hx_boost: false,
                });
            }
        }
    }

    let total = results.len();
    results.truncate(SEARCH_LIMIT);

    SearchSection {
        title: "Tech News".to_string(),
        href: "/wiki".to_string(),
        total,
        results,
    }
}
