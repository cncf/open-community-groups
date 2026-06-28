//! Background workers for publishing meeting recordings.

use std::{
    sync::Arc,
    time::{Duration, Instant},
};

use anyhow::Result;
use chrono::{DateTime, Utc};
use reqwest::Client as HttpClient;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use tokio::{sync::Mutex, time::sleep};
use tokio_util::{sync::CancellationToken, task::TaskTracker};
use tracing::{error, instrument, trace};

use crate::{
    config::{RecordingPublishingYouTubeConfig, YouTubeVideoVisibility},
    db::{DynDB, meetings::GoogleMeetRecordingPublishCandidate},
};

/// Google Drive API base URL.
const GOOGLE_DRIVE_BASE_URL: &str = "https://www.googleapis.com/drive/v3";
/// Google OAuth token endpoint.
const GOOGLE_TOKEN_URL: &str = "https://oauth2.googleapis.com/token";
/// `YouTube` upload API base URL.
const YOUTUBE_UPLOAD_URL: &str = "https://www.googleapis.com/upload/youtube/v3/videos";
/// Timeout for Google media API requests.
const HTTP_TIMEOUT: Duration = Duration::from_mins(1);
/// Token refresh margin.
const TOKEN_EXPIRY_MARGIN: Duration = Duration::from_mins(5);
/// Number of concurrent publishing workers.
const NUM_PUBLISH_WORKERS: usize = 1;
/// Number of claim recovery workers.
const NUM_RECOVERY_WORKERS: usize = 1;
/// Time after which claimed publishing requires recovery.
const PUBLISH_PROCESSING_TIMEOUT: Duration = Duration::from_hours(1);
/// Pause after a publishing error.
const PAUSE_ON_PUBLISH_ERROR: Duration = Duration::from_secs(30);
/// Pause when no recordings are ready.
const PAUSE_ON_PUBLISH_NONE: Duration = Duration::from_mins(5);
/// Pause after a recovery error.
const PAUSE_ON_RECOVERY_ERROR: Duration = Duration::from_secs(30);
/// Pause between recovery checks.
const PAUSE_ON_RECOVERY_NONE: Duration = Duration::from_mins(5);

/// Recording publishing manager.
pub(crate) struct RecordingPublishingManager;

impl RecordingPublishingManager {
    /// Create recording publishing workers when `YouTube` publishing is configured.
    pub(crate) fn new(
        db: &DynDB,
        cfg: &RecordingPublishingYouTubeConfig,
        task_tracker: &TaskTracker,
        cancellation_token: &CancellationToken,
    ) -> Self {
        let client = Arc::new(GoogleMediaClient::new(cfg.clone()));
        let publish_delay =
            Duration::from_secs(u64::try_from(cfg.publish_delay_minutes).unwrap_or_default() * 60);
        let retry_delay =
            Duration::from_secs(u64::try_from(cfg.retry_delay_minutes).unwrap_or(15) * 60);

        for _ in 1..=NUM_PUBLISH_WORKERS {
            let worker = PublishWorker {
                cancellation_token: cancellation_token.clone(),
                client: client.clone(),
                db: db.clone(),
                publish_delay,
                retry_delay,
            };
            task_tracker.spawn(async move {
                worker.run().await;
            });
        }

        for _ in 1..=NUM_RECOVERY_WORKERS {
            let worker = RecoveryWorker {
                cancellation_token: cancellation_token.clone(),
                db: db.clone(),
            };
            task_tracker.spawn(async move {
                worker.run().await;
            });
        }

        Self
    }
}

/// Worker that publishes completed Google Meet recordings.
struct PublishWorker {
    cancellation_token: CancellationToken,
    client: Arc<GoogleMediaClient>,
    db: DynDB,
    publish_delay: Duration,
    retry_delay: Duration,
}

impl PublishWorker {
    /// Main worker loop.
    async fn run(&self) {
        loop {
            match self.publish_recording().await {
                Ok(true) => {}
                Ok(false) => tokio::select! {
                    () = sleep(PAUSE_ON_PUBLISH_NONE) => {},
                    () = self.cancellation_token.cancelled() => break,
                },
                Err(err) => {
                    error!(%err, "error publishing meeting recording");
                    tokio::select! {
                        () = sleep(PAUSE_ON_PUBLISH_ERROR) => {},
                        () = self.cancellation_token.cancelled() => break,
                    }
                }
            }

            if self.cancellation_token.is_cancelled() {
                break;
            }
        }
    }

    /// Publish one claimed recording if available.
    #[instrument(skip(self), err)]
    async fn publish_recording(&self) -> Result<bool, PublishError> {
        let Some(candidate) = self
            .db
            .claim_google_meet_recording_for_publish(self.publish_delay, self.retry_delay)
            .await
            .map_err(PublishError::Other)?
        else {
            return Ok(false);
        };

        let recording = match self.client.find_recording(&candidate).await {
            Ok(Some(recording)) => recording,
            Ok(None) => {
                self.db
                    .release_google_meet_recording_publish_claim(
                        &candidate,
                        "google meet recording not found yet",
                    )
                    .await
                    .map_err(PublishError::Other)?;
                return Ok(true);
            }
            Err(err) => {
                self.release_claim(&candidate, &err.to_string()).await?;
                return Err(PublishError::Google(err));
            }
        };

        let uploaded = match self.client.upload_to_youtube(&candidate, &recording).await {
            Ok(uploaded) => uploaded,
            Err(err) => {
                self.release_claim(&candidate, &err.to_string()).await?;
                return Err(PublishError::Google(err));
            }
        };

        self.db
            .mark_google_meet_recording_published(&candidate, &recording.id, &uploaded.watch_url())
            .await
            .map_err(PublishError::Other)?;

        Ok(true)
    }

    /// Release a publish claim after retryable provider failures.
    async fn release_claim(
        &self,
        candidate: &GoogleMeetRecordingPublishCandidate,
        error: &str,
    ) -> Result<(), PublishError> {
        self.db
            .release_google_meet_recording_publish_claim(candidate, error)
            .await
            .map_err(PublishError::Other)
    }
}

/// Worker that recovers stale recording publish claims.
struct RecoveryWorker {
    cancellation_token: CancellationToken,
    db: DynDB,
}

impl RecoveryWorker {
    /// Main worker loop.
    async fn run(&self) {
        loop {
            let pause = match self.recover_claims().await {
                Ok(_) => PAUSE_ON_RECOVERY_NONE,
                Err(err) => {
                    error!(%err, "error recovering recording publish claims");
                    PAUSE_ON_RECOVERY_ERROR
                }
            };

            tokio::select! {
                () = sleep(pause) => {},
                () = self.cancellation_token.cancelled() => break,
            }
        }
    }

    /// Recover stale claims.
    #[instrument(skip(self), err)]
    async fn recover_claims(&self) -> Result<usize> {
        self.db
            .mark_stale_google_meet_recording_publish_claims_unknown(PUBLISH_PROCESSING_TIMEOUT)
            .await
    }
}

/// Google media client for Drive discovery and `YouTube` uploads.
struct GoogleMediaClient {
    cfg: RecordingPublishingYouTubeConfig,
    http_client: HttpClient,
    token: Mutex<Option<CachedToken>>,
}

impl GoogleMediaClient {
    /// Create a new Google media client.
    fn new(cfg: RecordingPublishingYouTubeConfig) -> Self {
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

    /// Find the most likely Drive recording for a meeting.
    #[instrument(skip(self, candidate), err)]
    async fn find_recording(
        &self,
        candidate: &GoogleMeetRecordingPublishCandidate,
    ) -> Result<Option<DriveRecording>, GoogleMediaError> {
        trace!("google media client: find recording");

        let token = self.get_token().await?;
        let query = drive_recording_query(candidate, self.cfg.drive_folder_id.as_deref());
        let query_string = serde_urlencoded::to_string([
            ("q", query.as_str()),
            ("fields", "files(id,name,mimeType,createdTime)"),
            ("orderBy", "createdTime desc"),
            ("pageSize", "1"),
        ])
        .map_err(|e| GoogleMediaError::Client(e.to_string()))?;
        let response = self
            .http_client
            .get(format!("{GOOGLE_DRIVE_BASE_URL}/files?{query_string}"))
            .bearer_auth(token)
            .send()
            .await
            .map_err(|e| GoogleMediaError::Network(e.to_string()))?;
        if !response.status().is_success() {
            return Err(GoogleMediaError::from_response(response).await);
        }

        let response = response
            .json::<DriveFilesResponse>()
            .await
            .map_err(|e| GoogleMediaError::Network(e.to_string()))?;

        Ok(response.files.into_iter().next())
    }

    /// Upload a Drive recording to `YouTube`.
    #[instrument(skip(self, candidate, recording), err)]
    async fn upload_to_youtube(
        &self,
        candidate: &GoogleMeetRecordingPublishCandidate,
        recording: &DriveRecording,
    ) -> Result<YouTubeVideo, GoogleMediaError> {
        trace!("google media client: upload recording");

        let token = self.get_token().await?;
        let media = self.download_drive_file(&token, recording).await?;
        let metadata = YouTubeVideoInsertRequest::from_candidate(candidate, self.cfg.visibility);
        let init_response = self
            .http_client
            .post(format!(
                "{YOUTUBE_UPLOAD_URL}?part=snippet,status&uploadType=resumable"
            ))
            .bearer_auth(&token)
            .header("X-Upload-Content-Type", &recording.mime_type)
            .header("X-Upload-Content-Length", media.len())
            .json(&metadata)
            .send()
            .await
            .map_err(|e| GoogleMediaError::Network(e.to_string()))?;
        if !init_response.status().is_success() {
            return Err(GoogleMediaError::from_response(init_response).await);
        }

        let upload_url = init_response
            .headers()
            .get(reqwest::header::LOCATION)
            .and_then(|value| value.to_str().ok())
            .ok_or_else(|| {
                GoogleMediaError::Client("youtube upload response missing location".to_string())
            })?
            .to_string();

        let upload_response = self
            .http_client
            .put(upload_url)
            .bearer_auth(token)
            .header(reqwest::header::CONTENT_TYPE, &recording.mime_type)
            .body(media)
            .send()
            .await
            .map_err(|e| GoogleMediaError::Network(e.to_string()))?;
        if !upload_response.status().is_success() {
            return Err(GoogleMediaError::from_response(upload_response).await);
        }

        upload_response
            .json::<YouTubeVideo>()
            .await
            .map_err(|e| GoogleMediaError::Network(e.to_string()))
    }

    /// Download Drive media bytes.
    async fn download_drive_file(
        &self,
        token: &str,
        recording: &DriveRecording,
    ) -> Result<Vec<u8>, GoogleMediaError> {
        let response = self
            .http_client
            .get(format!(
                "{GOOGLE_DRIVE_BASE_URL}/files/{}?alt=media",
                recording.id
            ))
            .bearer_auth(token)
            .send()
            .await
            .map_err(|e| GoogleMediaError::Network(e.to_string()))?;
        if !response.status().is_success() {
            return Err(GoogleMediaError::from_response(response).await);
        }

        let bytes = response
            .bytes()
            .await
            .map_err(|e| GoogleMediaError::Network(e.to_string()))?;

        Ok(bytes.to_vec())
    }

    /// Fetch a new OAuth access token.
    async fn fetch_token(&self) -> Result<CachedToken, GoogleMediaError> {
        let params = [
            ("client_id", self.cfg.client_id.as_str()),
            ("client_secret", self.cfg.client_secret.as_str()),
            ("refresh_token", self.cfg.refresh_token.as_str()),
            ("grant_type", "refresh_token"),
        ];
        let body = serde_urlencoded::to_string(params)
            .map_err(|e| GoogleMediaError::Token(e.to_string()))?;
        let response = self
            .http_client
            .post(GOOGLE_TOKEN_URL)
            .header("Content-Type", "application/x-www-form-urlencoded")
            .body(body)
            .send()
            .await
            .map_err(|e| GoogleMediaError::Network(e.to_string()))?;
        if !response.status().is_success() {
            let error: GoogleTokenErrorResponse = response.json().await.unwrap_or_default();
            return Err(GoogleMediaError::Token(format!(
                "{} - {}",
                error.error, error.error_description
            )));
        }

        let token_response: TokenResponse = response
            .json()
            .await
            .map_err(|e| GoogleMediaError::Network(e.to_string()))?;
        let expires_at = Instant::now() + Duration::from_secs(token_response.expires_in);

        Ok(CachedToken {
            access_token: token_response.access_token,
            expires_at,
        })
    }

    /// Get a valid access token.
    async fn get_token(&self) -> Result<String, GoogleMediaError> {
        let mut token_guard = self.token.lock().await;
        if let Some(ref cached) = *token_guard
            && Instant::now() + TOKEN_EXPIRY_MARGIN < cached.expires_at
        {
            return Ok(cached.access_token.clone());
        }

        let token = self.fetch_token().await?;
        let access_token = token.access_token.clone();
        *token_guard = Some(token);

        Ok(access_token)
    }
}

/// Cached OAuth token.
struct CachedToken {
    access_token: String,
    expires_at: Instant,
}

/// Drive recording metadata.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DriveRecording {
    #[serde(rename = "createdTime")]
    _created_time: DateTime<Utc>,
    id: String,
    mime_type: String,
    #[serde(rename = "name")]
    _name: String,
}

/// Drive files response.
#[derive(Debug, Deserialize)]
struct DriveFilesResponse {
    files: Vec<DriveRecording>,
}

/// `YouTube` insert metadata.
#[skip_serializing_none]
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct YouTubeVideoInsertRequest {
    snippet: YouTubeVideoSnippet,
    status: YouTubeVideoStatus,
}

impl YouTubeVideoInsertRequest {
    /// Build upload metadata from a meeting candidate.
    fn from_candidate(
        candidate: &GoogleMeetRecordingPublishCandidate,
        visibility: YouTubeVideoVisibility,
    ) -> Self {
        Self {
            snippet: YouTubeVideoSnippet {
                description: Some(format!(
                    "Recording for {} on {}.",
                    candidate.topic,
                    candidate.starts_at.format("%Y-%m-%d")
                )),
                title: candidate.topic.clone(),
            },
            status: YouTubeVideoStatus {
                privacy_status: visibility.to_string(),
                self_declared_made_for_kids: false,
            },
        }
    }
}

/// `YouTube` snippet metadata.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct YouTubeVideoSnippet {
    description: Option<String>,
    title: String,
}

/// `YouTube` status metadata.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct YouTubeVideoStatus {
    privacy_status: String,
    self_declared_made_for_kids: bool,
}

/// `YouTube` upload response.
#[derive(Debug, Deserialize)]
struct YouTubeVideo {
    id: String,
}

impl YouTubeVideo {
    /// Return the public watch URL for this video.
    fn watch_url(&self) -> String {
        format!("https://youtu.be/{}", self.id)
    }
}

/// Google media client errors.
#[derive(Debug)]
enum GoogleMediaError {
    Client(String),
    Network(String),
    RateLimit { retry_after: Duration },
    Server(String),
    Token(String),
}

impl std::fmt::Display for GoogleMediaError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Client(msg) => write!(f, "google media client error: {msg}"),
            Self::Network(msg) => write!(f, "google media network error: {msg}"),
            Self::RateLimit { retry_after } => {
                write!(
                    f,
                    "google media rate limit exceeded (retry after {}s)",
                    retry_after.as_secs()
                )
            }
            Self::Server(msg) => write!(f, "google media server error: {msg}"),
            Self::Token(msg) => write!(f, "google media token error: {msg}"),
        }
    }
}

impl std::error::Error for GoogleMediaError {}

impl GoogleMediaError {
    /// Create an error from an HTTP response.
    async fn from_response(response: reqwest::Response) -> Self {
        let retry_after = response
            .headers()
            .get(reqwest::header::RETRY_AFTER)
            .and_then(|v| v.to_str().ok())
            .and_then(|s| s.parse::<u64>().ok())
            .map_or(Duration::from_mins(1), Duration::from_secs);
        let status = response.status();
        let error: GoogleApiErrorEnvelope = response.json().await.unwrap_or_default();
        let message = if error.error.message.is_empty() {
            status.to_string()
        } else {
            error.error.message
        };

        if status == reqwest::StatusCode::TOO_MANY_REQUESTS {
            Self::RateLimit { retry_after }
        } else if status == reqwest::StatusCode::UNAUTHORIZED
            || status == reqwest::StatusCode::FORBIDDEN
        {
            Self::Token(message)
        } else if status.is_client_error() {
            Self::Client(message)
        } else {
            Self::Server(message)
        }
    }
}

/// Worker-level publish error.
#[derive(Debug)]
enum PublishError {
    Google(GoogleMediaError),
    Other(anyhow::Error),
}

impl std::fmt::Display for PublishError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Google(err) => write!(f, "{err}"),
            Self::Other(err) => write!(f, "{err}"),
        }
    }
}

impl std::error::Error for PublishError {}

/// Google API error envelope.
#[derive(Debug, Default, Deserialize)]
struct GoogleApiErrorEnvelope {
    #[serde(default)]
    error: GoogleApiError,
}

/// Google API error body.
#[derive(Debug, Default, Deserialize)]
struct GoogleApiError {
    #[serde(default)]
    message: String,
}

/// Google OAuth token response.
#[derive(Debug, Deserialize)]
struct TokenResponse {
    access_token: String,
    expires_in: u64,
}

/// Google OAuth token error response.
#[derive(Debug, Default, Deserialize)]
struct GoogleTokenErrorResponse {
    #[serde(default)]
    error: String,
    #[serde(default)]
    error_description: String,
}

/// Build a Drive query for likely Google Meet recording video files.
fn drive_recording_query(
    candidate: &GoogleMeetRecordingPublishCandidate,
    folder_id: Option<&str>,
) -> String {
    let mut parts = vec![
        "trashed = false".to_string(),
        "mimeType contains 'video/'".to_string(),
        format!(
            "createdTime >= '{}'",
            candidate
                .starts_at
                .checked_sub_signed(chrono::Duration::minutes(10))
                .unwrap_or(candidate.starts_at)
                .to_rfc3339()
        ),
    ];

    if let Some(folder_id) = folder_id.filter(|value| !value.trim().is_empty()) {
        parts.push(format!(
            "'{}' in parents",
            escape_drive_query_value(folder_id)
        ));
    }

    parts.join(" and ")
}

/// Escape single quotes in a Drive query string literal.
fn escape_drive_query_value(value: &str) -> String {
    value.replace('\\', "\\\\").replace('\'', "\\'")
}

#[cfg(test)]
mod tests {
    use chrono::TimeZone;
    use serde_json::json;
    use uuid::Uuid;

    use super::*;

    #[test]
    fn youtube_metadata_uses_unlisted_visibility() {
        let candidate = sample_candidate();
        let value = serde_json::to_value(YouTubeVideoInsertRequest::from_candidate(
            &candidate,
            YouTubeVideoVisibility::Unlisted,
        ))
        .unwrap();

        assert_eq!(value["snippet"]["title"], json!("Demo Recording"));
        assert_eq!(value["status"]["privacyStatus"], json!("unlisted"));
        assert_eq!(value["status"]["selfDeclaredMadeForKids"], json!(false));
    }

    #[test]
    fn drive_recording_query_includes_folder_and_time_window() {
        let candidate = sample_candidate();
        let query = drive_recording_query(&candidate, Some("folder'id"));

        assert!(query.contains("trashed = false"));
        assert!(query.contains("mimeType contains 'video/'"));
        assert!(query.contains("'folder\\'id' in parents"));
        assert!(query.contains("createdTime >= '2026-01-01T11:50:00+00:00'"));
    }

    fn sample_candidate() -> GoogleMeetRecordingPublishCandidate {
        GoogleMeetRecordingPublishCandidate {
            ends_at: Utc.with_ymd_and_hms(2026, 1, 1, 13, 0, 0).unwrap(),
            event_id: Some(Uuid::nil()),
            meeting_id: Uuid::nil(),
            provider_meeting_id: "calendar-event-id".to_string(),
            recording_publish_claimed_at: Utc.with_ymd_and_hms(2026, 1, 1, 14, 0, 0).unwrap(),
            session_id: None,
            starts_at: Utc.with_ymd_and_hms(2026, 1, 1, 12, 0, 0).unwrap(),
            timezone: Some("UTC".to_string()),
            topic: "Demo Recording".to_string(),
        }
    }
}
