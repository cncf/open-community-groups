//! HTTP handlers for the public landscape page.

use std::time::Duration;

use askama::Template;
use axum::{
    extract::{RawQuery, State},
    response::{Html, IntoResponse},
};
use cached::cached;
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
        site::landscape::{self, GitHubProjectLeaderboardEntry, GitHubRepositoryMetrics},
    },
    types::{landscape::LandscapeFilters, pagination::NavigationLinks},
};

const LANDSCAPE_URL: &str = "/landscape";
const GITHUB_PROJECT_KIND: &str = "github_project";
const GITHUB_LEADERBOARD_LIMIT: usize = 25;

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
        load_github_leaderboard(&github_output.entries).await
    } else {
        Vec::new()
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

async fn load_github_leaderboard(
    entries: &[crate::types::landscape::LandscapeEntry],
) -> Vec<GitHubProjectLeaderboardEntry> {
    let mut leaderboard = Vec::new();

    for entry in entries {
        let Some(github_url) = entry.github_url.as_deref() else {
            continue;
        };
        let Some((owner, repo)) = parse_github_repository_url(github_url) else {
            continue;
        };
        let Some(metrics) = fetch_github_repository_metrics(owner.clone(), repo.clone()).await
        else {
            continue;
        };

        leaderboard.push(GitHubProjectLeaderboardEntry {
            entry: entry.clone(),
            repository: format!("{owner}/{repo}"),
            score: metrics.stargazers_count,
            metrics,
        });
    }

    leaderboard.sort_by_key(|project| {
        (
            std::cmp::Reverse(project.score),
            std::cmp::Reverse(project.metrics.forks_count),
            project.entry.name.to_lowercase(),
        )
    });
    leaderboard.truncate(10);
    leaderboard
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
}

impl From<GitHubRepositoryResponse> for GitHubRepositoryMetrics {
    fn from(value: GitHubRepositoryResponse) -> Self {
        Self {
            stargazers_count: value.stargazers_count,
            forks_count: value.forks_count,
            open_issues_count: value.open_issues_count,
            watchers_count: value.subscribers_count.unwrap_or(value.watchers_count),
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
}
