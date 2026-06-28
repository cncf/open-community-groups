//! HTTP handlers for the public landscape page.

use std::{cmp::Reverse, time::Duration};

use askama::Template;
use axum::{
    extract::{RawQuery, State},
    response::{Html, IntoResponse},
};
use cached::cached;
use chrono::{DateTime, Utc};
use garde::Validate;
use reqwest::Url;
use serde::Deserialize;
use tracing::{debug, instrument};

use crate::{
    auth::AuthSession,
    db::DynDB,
    handlers::{error::HandlerError, extend_public_shared_cache_headers},
    router::serde_qs_config,
    templates::{
        PageId,
        auth::User,
        site::landscape::{
            self, GitHubLeaderboard, GitHubProjectLeaderboardEntry, GitHubRepositoryMetrics,
        },
    },
    types::{landscape::LandscapeFilters, pagination::NavigationLinks},
};

const LANDSCAPE_URL: &str = "/landscape";
const GITHUB_PROJECT_KIND: &str = "github_project";
const GITHUB_LEADERBOARD_LIMIT: usize = 25;
const GITHUB_LEADERBOARD_DISPLAY_LIMIT: usize = 10;
const GITHUB_SORT_STARS: &str = "stars";
const GITHUB_SORT_FORKS: &str = "forks";
const GITHUB_SORT_UPDATED: &str = "updated";

/// Render the public landscape listing page.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    let filters = parse_filters(raw_query.as_deref().unwrap_or_default())?;
    let github_filters = github_leaderboard_filters(&filters);
    let (output, github_output, site_settings) = tokio::try_join!(
        db.search_landscape_entries(&filters),
        db.search_landscape_entries(&github_filters),
        db.get_site_settings()
    )?;
    let navigation_links =
        NavigationLinks::from_filters(&filters, output.total, LANDSCAPE_URL, LANDSCAPE_URL)?;
    let github_leaderboard = if should_show_github_leaderboard(&filters) {
        load_github_leaderboard(&github_output.entries, github_leaderboard_sort(&filters)).await
    } else {
        GitHubLeaderboard::default()
    };

    let template = landscape::Page {
        page_id: PageId::SiteLandscape,
        path: LANDSCAPE_URL.to_string(),
        site_settings,
        user: User::from_session(auth_session).await?,
        filters,
        github_leaderboard,
        entries: output.entries,
        total: output.total,
        navigation_links,
    };

    Ok((
        extend_public_shared_cache_headers(&[])?,
        Html(template.render()?),
    ))
}

fn parse_filters(raw_query: &str) -> Result<LandscapeFilters, HandlerError> {
    let filters: LandscapeFilters = if raw_query.is_empty() {
        LandscapeFilters::default()
    } else {
        serde_qs_config().deserialize_str(raw_query)?
    };
    filters.validate()?;
    Ok(filters)
}

fn github_leaderboard_filters(filters: &LandscapeFilters) -> LandscapeFilters {
    LandscapeFilters {
        kind: Some(GITHUB_PROJECT_KIND.to_string()),
        limit: Some(GITHUB_LEADERBOARD_LIMIT),
        offset: Some(0),
        ..filters.clone()
    }
}

fn should_show_github_leaderboard(filters: &LandscapeFilters) -> bool {
    filters.kind.as_deref().is_none_or(|kind| kind == GITHUB_PROJECT_KIND)
}

fn github_leaderboard_sort(filters: &LandscapeFilters) -> &'static str {
    match filters.github_sort.as_deref() {
        Some(GITHUB_SORT_FORKS) => GITHUB_SORT_FORKS,
        Some(GITHUB_SORT_UPDATED) => GITHUB_SORT_UPDATED,
        _ => GITHUB_SORT_STARS,
    }
}

async fn load_github_leaderboard(
    entries: &[crate::types::landscape::LandscapeEntry],
    sort: &'static str,
) -> GitHubLeaderboard {
    let mut leaderboard = Vec::new();
    let mut attempted_count = 0;
    let mut unavailable_count = 0;

    for entry in entries {
        let Some(github_url) = entry.github_url.as_deref() else {
            continue;
        };
        let Some((owner, repo)) = parse_github_repository_url(github_url) else {
            continue;
        };
        attempted_count += 1;
        let Some(metrics) = fetch_github_repository_metrics(owner.clone(), repo.clone()).await
        else {
            unavailable_count += 1;
            continue;
        };

        leaderboard.push(GitHubProjectLeaderboardEntry {
            entry: entry.clone(),
            repository: format!("{owner}/{repo}"),
            score: leaderboard_score(&metrics, sort),
            metrics,
        });
    }

    sort_github_leaderboard(&mut leaderboard, sort);
    leaderboard.truncate(GITHUB_LEADERBOARD_DISPLAY_LIMIT);
    GitHubLeaderboard {
        entries: leaderboard,
        attempted_count,
        unavailable_count,
        sort: sort.to_string(),
    }
}

fn leaderboard_score(metrics: &GitHubRepositoryMetrics, sort: &str) -> i64 {
    match sort {
        GITHUB_SORT_FORKS => metrics.forks_count,
        _ => metrics.stargazers_count,
    }
}

fn sort_github_leaderboard(leaderboard: &mut [GitHubProjectLeaderboardEntry], sort: &str) {
    match sort {
        GITHUB_SORT_FORKS => leaderboard.sort_by_key(|project| {
            (
                Reverse(project.metrics.forks_count),
                Reverse(project.metrics.stargazers_count),
                project.entry.name.to_lowercase(),
            )
        }),
        GITHUB_SORT_UPDATED => leaderboard.sort_by_key(|project| {
            (
                Reverse(project.metrics.updated_at),
                Reverse(project.metrics.stargazers_count),
                project.entry.name.to_lowercase(),
            )
        }),
        _ => leaderboard.sort_by_key(|project| {
            (
                Reverse(project.metrics.stargazers_count),
                Reverse(project.metrics.forks_count),
                project.entry.name.to_lowercase(),
            )
        }),
    }
}

fn parse_github_repository_url(url: &str) -> Option<(String, String)> {
    let url = Url::parse(url).ok()?;
    if url.host_str()? != "github.com" {
        return None;
    }

    let mut segments = url.path_segments()?;
    let owner = segments.next()?.trim();
    let repo = segments.next()?.trim().trim_end_matches(".git");
    if owner.is_empty() || repo.is_empty() {
        return None;
    }

    Some((owner.to_string(), repo.to_string()))
}

#[cached(ttl = 900)]
async fn fetch_github_repository_metrics(
    owner: String,
    repo: String,
) -> Option<GitHubRepositoryMetrics> {
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(5))
        .user_agent("GOUP Landscape/1.0")
        .build()
        .unwrap_or_else(|_| reqwest::Client::new());
    let url = format!("https://api.github.com/repos/{owner}/{repo}");
    let response = client.get(url).send().await;
    let response = match response {
        Ok(response) => response,
        Err(error) => {
            debug!("failed to fetch GitHub repository metrics for {owner}/{repo}: {error}");
            return None;
        }
    };

    match response.error_for_status() {
        Ok(response) => response.json::<GitHubRepositoryResponse>().await.ok().map(Into::into),
        Err(error) => {
            debug!("GitHub repository metrics unavailable for {owner}/{repo}: {error}");
            None
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
struct GitHubRepositoryResponse {
    stargazers_count: i64,
    forks_count: i64,
    open_issues_count: i64,
    watchers_count: i64,
    subscribers_count: Option<i64>,
    updated_at: Option<DateTime<Utc>>,
    pushed_at: Option<DateTime<Utc>>,
}

impl From<GitHubRepositoryResponse> for GitHubRepositoryMetrics {
    fn from(value: GitHubRepositoryResponse) -> Self {
        Self {
            stargazers_count: value.stargazers_count,
            forks_count: value.forks_count,
            open_issues_count: value.open_issues_count,
            watchers_count: value.subscribers_count.unwrap_or(value.watchers_count),
            updated_at: value.updated_at,
            pushed_at: value.pushed_at,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_github_repository_urls() {
        assert_eq!(
            parse_github_repository_url("https://github.com/rust-lang/rust"),
            Some(("rust-lang".to_string(), "rust".to_string()))
        );
        assert_eq!(
            parse_github_repository_url("https://github.com/owner/repo.git"),
            Some(("owner".to_string(), "repo".to_string()))
        );
        assert_eq!(
            parse_github_repository_url("https://github.com/owner"),
            None
        );
        assert_eq!(
            parse_github_repository_url("https://gitlab.com/owner/repo"),
            None
        );
    }

    #[test]
    fn normalizes_github_leaderboard_sort() {
        assert_eq!(
            github_leaderboard_sort(&LandscapeFilters {
                github_sort: Some(GITHUB_SORT_FORKS.to_string()),
                ..Default::default()
            }),
            GITHUB_SORT_FORKS
        );
        assert_eq!(
            github_leaderboard_sort(&LandscapeFilters {
                github_sort: Some(GITHUB_SORT_UPDATED.to_string()),
                ..Default::default()
            }),
            GITHUB_SORT_UPDATED
        );
        assert_eq!(
            github_leaderboard_sort(&LandscapeFilters {
                github_sort: Some("unknown".to_string()),
                ..Default::default()
            }),
            GITHUB_SORT_STARS
        );
    }
}
