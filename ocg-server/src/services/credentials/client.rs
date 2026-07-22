//! HTTP client for the CertDirectory credentials API (v1).
//!
//! Used by the OCG dashboard to issue badges to event attendees without
//! exposing attendee emails to the browser. The organizer's API key is
//! supplied per-request (from browser localStorage) and never stored in OCG.

use std::time::Duration;

use reqwest::Client as HttpClient;
use serde::{Deserialize, Serialize};
use tracing::{instrument, warn};
use uuid::Uuid;

/// Default CertDirectory production API origin (no trailing slash).
pub(crate) const DEFAULT_BASE_URL: &str = "https://credentials.certdirectory.io";

/// Timeout for outbound CertDirectory API calls.
const HTTP_TIMEOUT: Duration = Duration::from_secs(30);

/// Page size when listing credentials by badge.
const LIST_PAGE_SIZE: u32 = 100;

/// CertDirectory credentials HTTP client.
#[derive(Clone)]
pub(crate) struct CredentialsClient {
    /// CertDirectory origin, e.g. `https://credentials.certdirectory.io`.
    base_url: String,
    /// Shared HTTP client.
    http: HttpClient,
}

/// Errors returned by the credentials client.
#[derive(Debug, thiserror::Error)]
pub(crate) enum CredentialsError {
    /// Network / transport failure.
    #[error("network: {0}")]
    Network(String),
    /// Invalid or missing API key (401).
    #[error("unauthorized")]
    Unauthorized,
    /// Org not approved / no signing keys / forbidden (403).
    #[error("forbidden: {0}")]
    Forbidden(String),
    /// Monthly recipient quota reached.
    #[error("quota reached")]
    QuotaReached,
    /// Attendee already has an active non-expiring credential for this badge.
    #[error("duplicate (already active)")]
    Duplicate,
    /// Rate limited (429).
    #[error("rate limited")]
    RateLimited,
    /// Other client / validation error (400).
    #[error("bad request: {0}")]
    BadRequest(String),
    /// Badge or resource not found (404).
    #[error("not found")]
    NotFound,
    /// Unexpected response.
    #[error("unexpected: {0}")]
    Unexpected(String),
}

/// Successful issue result.
#[derive(Debug, Clone)]
pub(crate) struct IssueResult {
    /// Public credential identifier (e.g. `CRD-…`).
    pub credential_id: String,
    /// Public verify URL.
    pub verify_url: String,
    /// Credential status (`pending`, etc.).
    pub status: String,
}

/// One credential from a list response (email + status only — used server-side).
#[derive(Debug, Clone)]
pub(crate) struct ListedCredential {
    /// Recipient email (lowercased by CertDirectory).
    pub email: String,
    /// Credential status (`pending` / `valid` / `expired` / `revoked`).
    pub status: String,
    /// Public credential identifier.
    pub credential_id: String,
    /// Public verify URL.
    pub verify_url: String,
}

/// Badge details returned by `GET /api/v1/badges/:badgeId`.
#[derive(Debug, Clone)]
pub(crate) struct BadgeInfo {
    /// Badge / achievement UUID.
    pub id: String,
    /// Human-readable badge name.
    pub name: String,
    /// Whether the badge template is active.
    pub is_active: bool,
}

#[derive(Debug, Serialize)]
struct IssueBody<'a> {
    #[serde(rename = "badgeId")]
    badge_id: &'a str,
    recipient: IssueRecipient<'a>,
}

#[derive(Debug, Serialize)]
struct IssueRecipient<'a> {
    name: &'a str,
    email: &'a str,
}

#[derive(Debug, Deserialize)]
struct IssueResponse {
    credential: IssueCredentialBody,
}

#[derive(Debug, Deserialize)]
struct IssueCredentialBody {
    #[serde(rename = "credentialId")]
    credential_id: String,
    status: String,
    #[serde(rename = "verifyUrl")]
    verify_url: String,
}

#[derive(Debug, Deserialize)]
struct ListResponse {
    credentials: Vec<ListCredentialBody>,
    pagination: ListPagination,
}

#[derive(Debug, Deserialize)]
struct ListCredentialBody {
    #[serde(rename = "credentialId")]
    credential_id: String,
    status: String,
    recipient: ListRecipient,
    #[serde(rename = "verifyUrl")]
    verify_url: String,
}

#[derive(Debug, Deserialize)]
struct ListRecipient {
    email: String,
}

#[derive(Debug, Deserialize)]
struct ListPagination {
    #[serde(rename = "hasMore")]
    has_more: bool,
}

#[derive(Debug, Deserialize)]
struct BadgeResponse {
    badge: BadgeBody,
}

#[derive(Debug, Deserialize)]
struct BadgeBody {
    id: String,
    name: String,
    #[serde(rename = "isActive", default)]
    is_active: bool,
}

#[derive(Debug, Deserialize)]
struct ErrorBody {
    #[serde(default)]
    message: Option<String>,
    #[serde(default)]
    error: Option<String>,
}

impl CredentialsClient {
    /// Create a client pointed at `base_url` (trailing slash is stripped).
    pub(crate) fn new(base_url: impl Into<String>) -> Self {
        let base_url = base_url.into().trim_end_matches('/').to_string();
        let http = HttpClient::builder()
            .timeout(HTTP_TIMEOUT)
            .build()
            .expect("failed to build credentials http client");
        Self { base_url, http }
    }

    /// Create a client using the production CertDirectory origin.
    pub(crate) fn production() -> Self {
        Self::new(DEFAULT_BASE_URL)
    }

    /// Returns the configured CertDirectory origin (no trailing slash).
    pub(crate) fn base_url(&self) -> &str {
        &self.base_url
    }

    /// Fetch a badge by ID (validates API key + badge ownership).
    #[instrument(skip(self, api_key), err)]
    pub(crate) async fn get_badge(
        &self,
        api_key: &str,
        badge_id: &str,
    ) -> Result<BadgeInfo, CredentialsError> {
        Uuid::parse_str(badge_id).map_err(|_| {
            CredentialsError::BadRequest("badge ID must be a valid UUID".to_string())
        })?;

        let url = format!("{}/api/v1/badges/{badge_id}", self.base_url);
        let response = self
            .http
            .get(&url)
            .bearer_auth(api_key)
            .send()
            .await
            .map_err(|e| CredentialsError::Network(e.to_string()))?;

        let status = response.status();
        if status.is_success() {
            let parsed: BadgeResponse = response
                .json()
                .await
                .map_err(|e| CredentialsError::Network(e.to_string()))?;
            return Ok(BadgeInfo {
                id: parsed.badge.id,
                name: parsed.badge.name,
                is_active: parsed.badge.is_active,
            });
        }

        Err(Self::map_error(status, response).await)
    }

    /// Issue one credential to `email` for `badge_id`.
    #[instrument(skip(self, api_key, name, email), err)]
    pub(crate) async fn issue(
        &self,
        api_key: &str,
        badge_id: &str,
        name: &str,
        email: &str,
    ) -> Result<IssueResult, CredentialsError> {
        let url = format!("{}/api/v1/credentials", self.base_url);
        let body = IssueBody {
            badge_id,
            recipient: IssueRecipient { name, email },
        };

        let response = self
            .http
            .post(&url)
            .bearer_auth(api_key)
            .json(&body)
            .send()
            .await
            .map_err(|e| CredentialsError::Network(e.to_string()))?;

        let status = response.status();
        if status.as_u16() == 201 {
            let parsed: IssueResponse = response
                .json()
                .await
                .map_err(|e| CredentialsError::Network(e.to_string()))?;
            return Ok(IssueResult {
                credential_id: parsed.credential.credential_id,
                verify_url: parsed.credential.verify_url,
                status: parsed.credential.status,
            });
        }

        Err(Self::map_error(status, response).await)
    }

    /// List all credentials for a badge (paginated until exhausted).
    #[instrument(skip(self, api_key), err)]
    pub(crate) async fn list_by_badge(
        &self,
        api_key: &str,
        badge_id: &str,
    ) -> Result<Vec<ListedCredential>, CredentialsError> {
        // Validate badge_id early so we don't hit the API with garbage.
        Uuid::parse_str(badge_id).map_err(|_| {
            CredentialsError::BadRequest("badge ID must be a valid UUID".to_string())
        })?;

        let mut out = Vec::new();
        let mut offset: u32 = 0;

        loop {
            let url = format!(
                "{}/api/v1/credentials?badgeId={badge_id}&limit={LIST_PAGE_SIZE}&offset={offset}",
                self.base_url
            );
            let response = self
                .http
                .get(&url)
                .bearer_auth(api_key)
                .send()
                .await
                .map_err(|e| CredentialsError::Network(e.to_string()))?;

            let status = response.status();
            if !status.is_success() {
                return Err(Self::map_error(status, response).await);
            }

            let parsed: ListResponse = response
                .json()
                .await
                .map_err(|e| CredentialsError::Network(e.to_string()))?;

            for c in parsed.credentials {
                out.push(ListedCredential {
                    email: c.recipient.email.to_lowercase(),
                    status: c.status,
                    credential_id: c.credential_id,
                    verify_url: c.verify_url,
                });
            }

            if !parsed.pagination.has_more {
                break;
            }
            offset = offset.saturating_add(LIST_PAGE_SIZE);
        }

        Ok(out)
    }

    /// Map a non-success HTTP response into a typed error.
    async fn map_error(
        status: reqwest::StatusCode,
        response: reqwest::Response,
    ) -> CredentialsError {
        let body_text = response.text().await.unwrap_or_default();
        let message = serde_json::from_str::<ErrorBody>(&body_text)
            .ok()
            .and_then(|b| b.message.or(b.error))
            .unwrap_or_else(|| body_text.clone());

        match status.as_u16() {
            401 => CredentialsError::Unauthorized,
            403 => CredentialsError::Forbidden(message),
            404 => CredentialsError::NotFound,
            429 => CredentialsError::RateLimited,
            400 | 409 => {
                let lower = message.to_lowercase();
                if lower.contains("monthly recipient limit") || lower.contains("limit reached") {
                    CredentialsError::QuotaReached
                } else if lower.contains("already")
                    || lower.contains("duplicate")
                    || lower.contains("active")
                {
                    CredentialsError::Duplicate
                } else {
                    CredentialsError::BadRequest(message)
                }
            }
            code if (500..600).contains(&code) => {
                warn!(%status, %message, "credentials api server error");
                CredentialsError::Unexpected(format!("server error ({status}): {message}"))
            }
            _ => CredentialsError::Unexpected(format!("unexpected status {status}: {message}")),
        }
    }
}

/// Organizer-facing message for a credentials error (never includes emails/keys).
pub(crate) fn friendly(err: &CredentialsError) -> String {
    match err {
        CredentialsError::Unauthorized => {
            "Invalid API key — check the key in setup".to_string()
        }
        CredentialsError::Forbidden(msg) => {
            if msg.is_empty() {
                "Your CertDirectory organization isn't approved or has no signing keys".to_string()
            } else {
                format!("Forbidden: {msg}")
            }
        }
        CredentialsError::QuotaReached => {
            "Monthly recipient limit reached on CertDirectory".to_string()
        }
        CredentialsError::Duplicate => "Already issued".to_string(),
        CredentialsError::RateLimited => {
            "CertDirectory rate limit hit — try again in a moment".to_string()
        }
        CredentialsError::BadRequest(msg) => {
            if msg.is_empty() {
                "Bad request to CertDirectory".to_string()
            } else {
                msg.clone()
            }
        }
        CredentialsError::NotFound => {
            "Badge not found for this API key's organization".to_string()
        }
        CredentialsError::Network(_) | CredentialsError::Unexpected(_) => {
            "Couldn't reach CertDirectory — try again".to_string()
        }
    }
}
