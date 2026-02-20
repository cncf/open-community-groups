//! Lightweight Zoom client for meeting operations.

use std::time::{Duration, Instant};

use anyhow::{Result, anyhow};
use base64::{Engine, engine::general_purpose::STANDARD as BASE64};
use chrono::{DateTime, Utc};
use reqwest::Client as HttpClient;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use tokio::sync::Mutex;
use tracing::{instrument, trace};

use crate::{config::MeetingsZoomConfig, services::meetings::Meeting};

use super::MeetingProviderError;

/// Zoom client error code for "meeting does not exist".
pub(crate) const ZOOM_MEETING_NOT_FOUND: i32 = 3001;

/// Base URL for Zoom client v2.
const BASE_URL: &str = "https://api.zoom.us/v2";

/// Default retry delay when Zoom doesn't provide Retry-After header.
const DEFAULT_RATE_LIMIT_RETRY: Duration = Duration::from_secs(60);

/// Timeout for HTTP requests to Zoom API.
const HTTP_TIMEOUT: Duration = Duration::from_secs(20);

/// Maximum meeting duration in minutes.
const MAX_DURATION_MINUTES: i64 = 720;

/// Minimum meeting duration in minutes.
const MIN_DURATION_MINUTES: i64 = 5;

/// Margin before token expiry to trigger refresh.
const TOKEN_EXPIRY_MARGIN: Duration = Duration::from_secs(300);

/// Zoom user ID for Server-to-Server app owner.
const USER_ID: &str = "me";

/// Zoom OAuth token endpoint.
const ZOOM_TOKEN_URL: &str = "https://zoom.us/oauth/token";

/// Zoom client for meeting CRUD operations.
pub(crate) struct ZoomClient {
    cfg: MeetingsZoomConfig,
    http_client: HttpClient,

    token: Mutex<Option<CachedToken>>,
}

impl ZoomClient {
    /// Create a new Zoom client.
    pub(crate) fn new(cfg: MeetingsZoomConfig) -> Self {
        let http_client = HttpClient::builder()
            .timeout(HTTP_TIMEOUT)
            .build()
            .expect("failed to build http client");

        Self {
            cfg,
            http_client,
            token: Mutex::new(None),
        }
    }

    /// Create a new meeting.
    #[instrument(skip(self, req), err)]
    pub(crate) async fn create_meeting(
        &self,
        req: &CreateMeetingRequest,
    ) -> Result<ZoomMeeting, ZoomClientError> {
        trace!("zoom client: create meeting");

        let token = self
            .get_token()
            .await
            .map_err(|e| ZoomClientError::Token(e.to_string()))?;
        let url = format!("{BASE_URL}/users/{USER_ID}/meetings");
        let response = self
            .http_client
            .post(&url)
            .bearer_auth(token)
            .json(req)
            .send()
            .await
            .map_err(|e| ZoomClientError::Network(e.to_string()))?;
        if !response.status().is_success() {
            return Err(ZoomClientError::from_response(response).await);
        }

        response
            .json()
            .await
            .map_err(|e| ZoomClientError::Network(e.to_string()))
    }

    /// Delete a meeting by ID.
    #[instrument(skip(self), err)]
    pub(crate) async fn delete_meeting(&self, meeting_id: i64) -> Result<(), ZoomClientError> {
        trace!("zoom client: delete meeting");

        let token = self
            .get_token()
            .await
            .map_err(|e| ZoomClientError::Token(e.to_string()))?;
        let url = format!("{BASE_URL}/meetings/{meeting_id}");
        let response = self
            .http_client
            .delete(&url)
            .bearer_auth(token)
            .send()
            .await
            .map_err(|e| ZoomClientError::Network(e.to_string()))?;
        if !response.status().is_success() {
            return Err(ZoomClientError::from_response(response).await);
        }

        Ok(())
    }

    /// Get a meeting by ID.
    #[instrument(skip(self), err)]
    pub(crate) async fn get_meeting(&self, meeting_id: i64) -> Result<ZoomMeeting, ZoomClientError> {
        trace!("zoom client: get meeting");

        let token = self
            .get_token()
            .await
            .map_err(|e| ZoomClientError::Token(e.to_string()))?;
        let url = format!("{BASE_URL}/meetings/{meeting_id}");
        let response = self
            .http_client
            .get(&url)
            .bearer_auth(token)
            .send()
            .await
            .map_err(|e| ZoomClientError::Network(e.to_string()))?;
        if !response.status().is_success() {
            return Err(ZoomClientError::from_response(response).await);
        }

        response
            .json()
            .await
            .map_err(|e| ZoomClientError::Network(e.to_string()))
    }

    /// Update an existing meeting.
    #[instrument(skip(self, req), err)]
    pub(crate) async fn update_meeting(
        &self,
        meeting_id: i64,
        req: &UpdateMeetingRequest,
    ) -> Result<(), ZoomClientError> {
        trace!("zoom client: update meeting");

        let token = self
            .get_token()
            .await
            .map_err(|e| ZoomClientError::Token(e.to_string()))?;
        let url = format!("{BASE_URL}/meetings/{meeting_id}");
        let response = self
            .http_client
            .patch(&url)
            .bearer_auth(token)
            .json(req)
            .send()
            .await
            .map_err(|e| ZoomClientError::Network(e.to_string()))?;
        if !response.status().is_success() {
            return Err(ZoomClientError::from_response(response).await);
        }

        Ok(())
    }

    /// Fetch a new access token from Zoom using server-to-server OAuth.
    #[instrument(skip(self), err)]
    async fn fetch_token(&self) -> Result<CachedToken> {
        trace!("zoom client: fetch token");

        // Setup credentials
        let credentials = format!("{}:{}", self.cfg.client_id, self.cfg.client_secret);
        let encoded = BASE64.encode(credentials.as_bytes());

        // Make the token request
        let response = self
            .http_client
            .post(ZOOM_TOKEN_URL)
            .header("Authorization", format!("Basic {encoded}"))
            .header("Content-Type", "application/x-www-form-urlencoded")
            .body(format!(
                "grant_type=account_credentials&account_id={}",
                self.cfg.account_id
            ))
            .send()
            .await?;
        if !response.status().is_success() {
            let error: ZoomClientErrorResponse = response.json().await.unwrap_or_default();
            return Err(anyhow!("zoom token error: {} - {}", error.code, error.message));
        }

        // Parse the token response
        let token_response: TokenResponse = response.json().await?;
        let expires_at = Instant::now() + Duration::from_secs(token_response.expires_in);

        Ok(CachedToken {
            access_token: token_response.access_token,
            expires_at,
        })
    }

    /// Get a valid access token, fetching a new one if needed.
    async fn get_token(&self) -> Result<String> {
        // Check if we have a valid cached token
        let mut token_guard = self.token.lock().await;
        if let Some(ref cached) = *token_guard
            && Instant::now() + TOKEN_EXPIRY_MARGIN < cached.expires_at
        {
            return Ok(cached.access_token.clone());
        }

        // Fetch a new token
        let new_token = self.fetch_token().await?;
        let access_token = new_token.access_token.clone();
        *token_guard = Some(new_token);

        Ok(access_token)
    }
}

/// Cached OAuth access token with expiry tracking.
struct CachedToken {
    access_token: String,
    expires_at: Instant,
}

/// Request to create a new meeting.
#[skip_serializing_none]
#[derive(Debug, Serialize)]
pub(crate) struct CreateMeetingRequest {
    #[serde(rename = "type")]
    pub meeting_type: i32,
    pub topic: String,

    pub default_password: Option<bool>,
    pub duration: Option<Minutes>,
    pub settings: Option<MeetingSettings>,
    pub start_time: Option<DateTime<Utc>>,
    pub timezone: Option<String>,
}

impl TryFrom<&Meeting> for CreateMeetingRequest {
    type Error = ZoomClientError;

    fn try_from(m: &Meeting) -> Result<Self, Self::Error> {
        Ok(Self {
            meeting_type: 2, // Scheduled meeting
            topic: m.topic.clone().unwrap_or_default(),

            default_password: Some(true),
            duration: m.duration.map(Minutes::try_from_duration).transpose()?,
            settings: Some(default_meeting_settings()),
            start_time: m.starts_at,
            timezone: m.timezone.clone(),
        })
    }
}

/// Meeting settings configuration.
#[skip_serializing_none]
#[derive(Clone, Debug, Default, Serialize)]
pub(crate) struct MeetingSettings {
    pub auto_recording: Option<String>,
    pub jbh_time: Option<i32>,
    pub join_before_host: Option<bool>,
    pub mute_upon_entry: Option<bool>,
    pub participant_video: Option<bool>,
    pub waiting_room: Option<bool>,
}

/// Duration in minutes for Zoom client.
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(transparent)]
pub(crate) struct Minutes(pub i64);

impl Minutes {
    /// Validate and convert a duration to minutes.
    fn try_from_duration(d: std::time::Duration) -> Result<Self, ZoomClientError> {
        let minutes = i64::try_from(d.as_secs() / 60).unwrap_or(i64::MAX);
        if !(MIN_DURATION_MINUTES..=MAX_DURATION_MINUTES).contains(&minutes) {
            return Err(ZoomClientError::InvalidDuration { minutes });
        }
        Ok(Self(minutes))
    }
}

/// Response from Zoom's OAuth token endpoint.
#[derive(Debug, Deserialize)]
struct TokenResponse {
    access_token: String,
    expires_in: u64,
}

/// Request to update an existing meeting.
#[skip_serializing_none]
#[derive(Debug, Default, Serialize)]
pub(crate) struct UpdateMeetingRequest {
    pub duration: Option<Minutes>,
    pub settings: Option<MeetingSettings>,
    pub start_time: Option<DateTime<Utc>>,
    pub timezone: Option<String>,
    pub topic: Option<String>,
}

impl TryFrom<&Meeting> for UpdateMeetingRequest {
    type Error = ZoomClientError;

    fn try_from(m: &Meeting) -> Result<Self, Self::Error> {
        Ok(Self {
            duration: m.duration.map(Minutes::try_from_duration).transpose()?,
            settings: Some(default_meeting_settings()),
            start_time: m.starts_at,
            timezone: m.timezone.clone(),
            topic: m.topic.clone(),
        })
    }
}

/// Error types from Zoom client calls.
#[derive(Debug)]
pub(crate) enum ZoomClientError {
    /// Non-retryable client errors (4xx except 429).
    Client { code: i32, message: String },
    /// Invalid meeting duration (too short or too long).
    InvalidDuration { minutes: i64 },
    /// Network or connection errors (retryable).
    Network(String),
    /// Rate limit exceeded (retryable after delay).
    RateLimit { retry_after: Duration },
    /// Server errors (5xx, retryable).
    Server { code: i32, message: String },
    /// Token fetch error (retryable).
    Token(String),
}

impl std::fmt::Display for ZoomClientError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Client { code, message } => write!(f, "zoom client client error: {code} - {message}"),
            Self::InvalidDuration { minutes } => write!(f, "invalid meeting duration: {minutes} minutes"),
            Self::Network(msg) => write!(f, "zoom client network error: {msg}"),
            Self::RateLimit { retry_after } => {
                write!(
                    f,
                    "zoom client rate limit exceeded (retry after {}s)",
                    retry_after.as_secs()
                )
            }
            Self::Server { code, message } => write!(f, "zoom client server error: {code} - {message}"),
            Self::Token(msg) => write!(f, "zoom client token error: {msg}"),
        }
    }
}

impl std::error::Error for ZoomClientError {}

impl From<ZoomClientError> for MeetingProviderError {
    fn from(e: ZoomClientError) -> Self {
        match e {
            ZoomClientError::Client { code, message } => {
                if code == ZOOM_MEETING_NOT_FOUND {
                    Self::NotFound
                } else {
                    Self::Client(format!("{code}: {message}"))
                }
            }
            ZoomClientError::InvalidDuration { minutes } => {
                Self::Client(format!("invalid meeting duration: {minutes} minutes"))
            }
            ZoomClientError::Network(msg) => Self::Network(msg),
            ZoomClientError::RateLimit { retry_after } => Self::RateLimit { retry_after },
            ZoomClientError::Server { code, message } => Self::Server(format!("{code}: {message}")),
            ZoomClientError::Token(msg) => Self::Token(msg),
        }
    }
}

impl ZoomClientError {
    /// Create error from HTTP response status and body.
    async fn from_response(response: reqwest::Response) -> Self {
        // Parse Retry-After header before consuming response body
        let retry_after = response
            .headers()
            .get(reqwest::header::RETRY_AFTER)
            .and_then(|v| v.to_str().ok())
            .and_then(|s| s.parse::<u64>().ok())
            .map_or(DEFAULT_RATE_LIMIT_RETRY, Duration::from_secs);

        // Get status and parse error body
        let status = response.status();
        let error: ZoomClientErrorResponse = response.json().await.unwrap_or_default();

        // Determine error type based on status code
        if status == reqwest::StatusCode::TOO_MANY_REQUESTS {
            Self::RateLimit { retry_after }
        } else if status == reqwest::StatusCode::UNAUTHORIZED || status == reqwest::StatusCode::FORBIDDEN {
            // Auth errors are retryable (token may have expired)
            Self::Token(format!("{} - {}", error.code, error.message))
        } else if status.is_client_error() {
            Self::Client {
                code: error.code,
                message: error.message,
            }
        } else {
            Self::Server {
                code: error.code,
                message: error.message,
            }
        }
    }
}

/// Error response from Zoom client (for deserialization).
#[derive(Debug, Default, Deserialize)]
struct ZoomClientErrorResponse {
    #[serde(default)]
    code: i32,
    #[serde(default)]
    message: String,
}

/// Meeting response from Zoom client.
#[derive(Debug, Deserialize)]
pub(crate) struct ZoomMeeting {
    pub id: i64,
    pub join_url: String,
    pub password: Option<String>,
}

/// Returns the default settings applied to all meetings.
fn default_meeting_settings() -> MeetingSettings {
    MeetingSettings {
        auto_recording: Some("cloud".to_string()),
        jbh_time: Some(15),
        join_before_host: Some(true),
        mute_upon_entry: Some(true),
        participant_video: Some(false),
        waiting_room: Some(false),
    }
}
