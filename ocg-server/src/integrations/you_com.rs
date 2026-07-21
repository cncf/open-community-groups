//! You.com search integration used to discover Baku community events.

use std::{collections::HashSet, time::Duration};

use anyhow::{Context, Result, bail};
use chrono::{DateTime, Utc};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::config::YouComConfig;

const REQUEST_TIMEOUT: Duration = Duration::from_secs(20);

/// A normalized community event ready for persistence.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct DiscoveredEvent {
    pub title: String,
    pub description: Option<String>,
    pub starts_at: DateTime<Utc>,
    pub source_url: String,
}

impl DiscoveredEvent {
    /// A stable deduplication key scoped to a group.
    pub(crate) fn fingerprint(&self) -> String {
        let mut hasher = Sha256::new();
        hasher.update(self.title.trim().to_lowercase());
        hasher.update(b"\0");
        hasher.update(self.starts_at.timestamp().to_le_bytes());
        hasher.update(b"\0");
        hasher.update(self.source_url.trim().to_lowercase());
        hex::encode(hasher.finalize())
    }
}

/// Thin, typed client for the You.com search API.
#[derive(Clone)]
pub(crate) struct YouComClient {
    api_key: String,
    http: Client,
    search_url: String,
}

impl YouComClient {
    pub(crate) fn new(cfg: &YouComConfig) -> Result<Self> {
        let http = Client::builder().timeout(REQUEST_TIMEOUT).build()?;
        Ok(Self {
            api_key: cfg.api_key.clone(),
            http,
            search_url: cfg.search_url.clone(),
        })
    }

    /// Searches You.com for current Baku community-event pages.
    pub(crate) async fn search_baku_events(&self) -> Result<Vec<SearchResult>> {
        self.search("upcoming community events in Baku Azerbaijan").await
    }

    /// Searches You.com with a caller-provided, source-scoped query.
    pub(crate) async fn search(&self, query: &str) -> Result<Vec<SearchResult>> {
        let mut search_url =
            reqwest::Url::parse(&self.search_url).context("invalid You.com search URL")?;
        search_url.query_pairs_mut().append_pair("query", query);
        let response = self
            .http
            .get(search_url)
            .header("X-API-Key", &self.api_key)
            .send()
            .await
            .context("requesting You.com search")?
            .error_for_status()
            .context("You.com search returned an error")?;
        let payload: SearchResponse =
            response.json().await.context("decoding You.com search response")?;
        Ok(payload.results)
    }
}

/// Search result fields shared by the supported You.com response shapes.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct SearchResult {
    #[serde(alias = "name")]
    pub title: String,
    #[serde(alias = "url", alias = "link")]
    pub url: String,
    #[serde(default, alias = "snippet", alias = "description")]
    pub description: Option<String>,
}

#[derive(Debug, Deserialize)]
struct SearchResponse {
    #[serde(default, alias = "hits")]
    results: Vec<SearchResult>,
}

/// Rejects pages that do not identify Baku or Azerbaijan.
pub(crate) fn is_baku_relevant(result: &SearchResult) -> bool {
    let text = format!(
        "{} {} {}",
        result.title,
        result.description.as_deref().unwrap_or_default(),
        result.url
    )
    .to_lowercase();
    text.contains("baku") || text.contains("azerbaijan") || text.contains("azərbaycan")
}

/// Returns unique, relevant results while preserving discovery order.
pub(crate) fn unique_baku_results(results: Vec<SearchResult>) -> Vec<SearchResult> {
    let mut urls = HashSet::new();
    results
        .into_iter()
        .filter(is_baku_relevant)
        .filter(|result| urls.insert(result.url.trim().to_lowercase()))
        .collect()
}

/// Validates a source URL entered in a group dashboard.
pub(crate) fn validate_source_url(url: &str) -> Result<()> {
    let parsed = reqwest::Url::parse(url).context("source URL must be absolute")?;
    if !matches!(parsed.scheme(), "http" | "https") {
        bail!("source URL must use HTTP or HTTPS");
    }
    if parsed.host_str().is_none() {
        bail!("source URL must include a host");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use chrono::TimeZone;

    use super::*;

    fn result(title: &str, url: &str, description: Option<&str>) -> SearchResult {
        SearchResult {
            title: title.into(),
            url: url.into(),
            description: description.map(str::to_owned),
        }
    }

    #[test]
    fn retains_unique_baku_results() {
        let results = unique_baku_results(vec![
            result("Baku Rust meetup", "https://example.test/events/1", None),
            result("Baku Rust meetup", "https://example.test/events/1", None),
            result("Tbilisi meetup", "https://example.test/events/2", None),
        ]);
        assert_eq!(results.len(), 1);
    }

    #[test]
    fn fingerprint_changes_when_event_time_changes() {
        let event = DiscoveredEvent {
            title: "Baku meetup".into(),
            description: None,
            starts_at: Utc.with_ymd_and_hms(2026, 7, 21, 12, 0, 0).unwrap(),
            source_url: "https://example.test/events/1".into(),
        };
        let mut rescheduled = event.clone();
        rescheduled.starts_at = Utc.with_ymd_and_hms(2026, 7, 22, 12, 0, 0).unwrap();
        assert_ne!(event.fingerprint(), rescheduled.fingerprint());
    }
}
