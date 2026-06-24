//! Lightweight Google Calendar client for Google Meet operations.

use std::time::{Duration, Instant};

use anyhow::{Result, anyhow};
use chrono::{DateTime, Utc};
use percent_encoding::{NON_ALPHANUMERIC, utf8_percent_encode};
use reqwest::Client as HttpClient;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use tokio::sync::Mutex;
use tracing::{instrument, trace};
use uuid::Uuid;

use crate::{config::MeetingsGoogleMeetConfig, services::meetings::Meeting};

use super::MeetingProviderError;

/// Google Calendar client error code for "event does not exist".
pub(crate) const GOOGLE_CALENDAR_EVENT_NOT_FOUND: i32 = 404;

/// Base URL for Google Calendar API v3.
const BASE_URL: &str = "https://www.googleapis.com/calendar/v3";

/// Timeout for HTTP requests to Google Calendar API.
const HTTP_TIMEOUT: Duration = Duration::from_secs(20);

/// Maximum meeting duration in minutes.
const MAX_DURATION_MINUTES: i64 = 720;

/// Minimum meeting duration in minutes.
const MIN_DURATION_MINUTES: i64 = 5;

/// Margin before token expiry to trigger refresh.
const TOKEN_EXPIRY_MARGIN: Duration = Duration::from_mins(5);

/// Google OAuth token endpoint.
const GOOGLE_TOKEN_URL: &str = "https://oauth2.googleapis.com/token";

/// Google Calendar client for event and Meet operations.
pub(crate) struct GoogleCalendarClient {
    cfg: MeetingsGoogleMeetConfig,
    http_client: HttpClient,
    token: Mutex<Option<CachedToken>>,
}

impl GoogleCalendarClient {
    /// Create a new Google Calendar client.
    pub(crate) fn new(cfg: MeetingsGoogleMeetConfig) -> Self {
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

    /// Create a Calendar event with Google Meet conference data.
    #[instrument(skip(self, req), err)]
    pub(crate) async fn create_event(
        &self,
        req: &CalendarEventRequest,
    ) -> Result<GoogleCalendarEvent, GoogleCalendarClientError> {
        trace!("google calendar client: create event");

        let token = self
            .get_token()
            .await
            .map_err(|e| GoogleCalendarClientError::Token(e.to_string()))?;
        let url = self.calendar_events_url("conferenceDataVersion=1");
        let request = req.clone().with_meet_conference();
        let response = self
            .http_client
            .post(&url)
            .bearer_auth(token)
            .json(&request)
            .send()
            .await
            .map_err(|e| GoogleCalendarClientError::Network(e.to_string()))?;
        if !response.status().is_success() {
            return Err(GoogleCalendarClientError::from_response(response).await);
        }

        let response = response
            .json::<CalendarEventResponse>()
            .await
            .map_err(|e| GoogleCalendarClientError::Network(e.to_string()))?;
        GoogleCalendarEvent::try_from(response)
    }

    /// Delete a Calendar event by ID.
    #[instrument(skip(self), err)]
    pub(crate) async fn delete_event(
        &self,
        event_id: &str,
    ) -> Result<(), GoogleCalendarClientError> {
        trace!("google calendar client: delete event");

        let token = self
            .get_token()
            .await
            .map_err(|e| GoogleCalendarClientError::Token(e.to_string()))?;
        let url = self.calendar_event_url(event_id, "");
        let response = self
            .http_client
            .delete(&url)
            .bearer_auth(token)
            .send()
            .await
            .map_err(|e| GoogleCalendarClientError::Network(e.to_string()))?;
        if !response.status().is_success() {
            return Err(GoogleCalendarClientError::from_response(response).await);
        }

        Ok(())
    }

    /// Get a Calendar event by ID.
    #[instrument(skip(self), err)]
    pub(crate) async fn get_event(
        &self,
        event_id: &str,
    ) -> Result<GoogleCalendarEvent, GoogleCalendarClientError> {
        trace!("google calendar client: get event");

        let token = self
            .get_token()
            .await
            .map_err(|e| GoogleCalendarClientError::Token(e.to_string()))?;
        let url = self.calendar_event_url(event_id, "conferenceDataVersion=1");
        let response = self
            .http_client
            .get(&url)
            .bearer_auth(token)
            .send()
            .await
            .map_err(|e| GoogleCalendarClientError::Network(e.to_string()))?;
        if !response.status().is_success() {
            return Err(GoogleCalendarClientError::from_response(response).await);
        }

        let response = response
            .json::<CalendarEventResponse>()
            .await
            .map_err(|e| GoogleCalendarClientError::Network(e.to_string()))?;
        GoogleCalendarEvent::try_from(response)
    }

    /// Update an existing Calendar event.
    #[instrument(skip(self, req), err)]
    pub(crate) async fn update_event(
        &self,
        event_id: &str,
        req: &CalendarEventRequest,
    ) -> Result<(), GoogleCalendarClientError> {
        trace!("google calendar client: update event");

        let token = self
            .get_token()
            .await
            .map_err(|e| GoogleCalendarClientError::Token(e.to_string()))?;
        let url = self.calendar_event_url(event_id, "conferenceDataVersion=1");
        let response = self
            .http_client
            .patch(&url)
            .bearer_auth(token)
            .json(req)
            .send()
            .await
            .map_err(|e| GoogleCalendarClientError::Network(e.to_string()))?;
        if !response.status().is_success() {
            return Err(GoogleCalendarClientError::from_response(response).await);
        }

        Ok(())
    }

    /// Fetch a new access token from Google using the configured refresh token.
    #[instrument(skip(self), err)]
    async fn fetch_token(&self) -> Result<CachedToken> {
        trace!("google calendar client: fetch token");

        let params = [
            ("client_id", self.cfg.client_id.as_str()),
            ("client_secret", self.cfg.client_secret.as_str()),
            ("refresh_token", self.cfg.refresh_token.as_str()),
            ("grant_type", "refresh_token"),
        ];
        let body = serde_urlencoded::to_string(params)?;
        let response = self
            .http_client
            .post(GOOGLE_TOKEN_URL)
            .header("Content-Type", "application/x-www-form-urlencoded")
            .body(body)
            .send()
            .await?;
        if !response.status().is_success() {
            let error: GoogleTokenErrorResponse = response.json().await.unwrap_or_default();
            return Err(anyhow!(
                "google token error: {} - {}",
                error.error,
                error.error_description
            ));
        }

        let token_response: TokenResponse = response.json().await?;
        let expires_at = Instant::now() + Duration::from_secs(token_response.expires_in);

        Ok(CachedToken {
            access_token: token_response.access_token,
            expires_at,
        })
    }

    /// Get a valid access token, fetching a new one if needed.
    async fn get_token(&self) -> Result<String> {
        let mut token_guard = self.token.lock().await;
        if let Some(ref cached) = *token_guard
            && Instant::now() + TOKEN_EXPIRY_MARGIN < cached.expires_at
        {
            return Ok(cached.access_token.clone());
        }

        let new_token = self.fetch_token().await?;
        let access_token = new_token.access_token.clone();
        *token_guard = Some(new_token);

        Ok(access_token)
    }

    /// Returns the events collection URL for the configured calendar.
    fn calendar_events_url(&self, query: &str) -> String {
        let calendar_id = utf8_percent_encode(&self.cfg.calendar_id, NON_ALPHANUMERIC);
        if query.is_empty() {
            format!("{BASE_URL}/calendars/{calendar_id}/events")
        } else {
            format!("{BASE_URL}/calendars/{calendar_id}/events?{query}")
        }
    }

    /// Returns a single event URL for the configured calendar.
    fn calendar_event_url(&self, event_id: &str, query: &str) -> String {
        let calendar_id = utf8_percent_encode(&self.cfg.calendar_id, NON_ALPHANUMERIC);
        let event_id = utf8_percent_encode(event_id, NON_ALPHANUMERIC);
        if query.is_empty() {
            format!("{BASE_URL}/calendars/{calendar_id}/events/{event_id}")
        } else {
            format!("{BASE_URL}/calendars/{calendar_id}/events/{event_id}?{query}")
        }
    }
}

/// Cached OAuth access token with expiry tracking.
struct CachedToken {
    access_token: String,
    expires_at: Instant,
}

/// Calendar event request used for create and update.
#[skip_serializing_none]
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct CalendarEventRequest {
    pub conference_data: Option<ConferenceData>,
    pub description: Option<String>,
    pub end: EventDateTime,
    pub start: EventDateTime,
    pub summary: String,
}

impl CalendarEventRequest {
    /// Adds a Google Meet conference creation request.
    fn with_meet_conference(mut self) -> Self {
        self.conference_data = Some(ConferenceData {
            create_request: ConferenceCreateRequest {
                conference_solution_key: ConferenceSolutionKey {
                    conference_type: "hangoutsMeet",
                },
                request_id: Uuid::new_v4().to_string(),
            },
        });
        self
    }
}

impl TryFrom<&Meeting> for CalendarEventRequest {
    type Error = GoogleCalendarClientError;

    fn try_from(m: &Meeting) -> Result<Self, Self::Error> {
        let starts_at = m.starts_at.ok_or_else(|| GoogleCalendarClientError::Client {
            code: 400,
            message: "missing meeting starts_at".to_string(),
        })?;
        let duration = m.duration.ok_or_else(|| GoogleCalendarClientError::Client {
            code: 400,
            message: "missing meeting duration".to_string(),
        })?;
        duration_minutes(duration)?;
        let duration = chrono::Duration::from_std(duration).map_err(|err| {
            GoogleCalendarClientError::Client {
                code: 400,
                message: err.to_string(),
            }
        })?;
        let ends_at = starts_at.checked_add_signed(duration).ok_or_else(|| {
            GoogleCalendarClientError::Client {
                code: 400,
                message: "meeting end time overflow".to_string(),
            }
        })?;
        let timezone = m.timezone.clone();

        Ok(Self {
            conference_data: None,
            description: m.hosts.as_ref().and_then(|hosts| {
                (!hosts.is_empty()).then(|| format!("Additional host emails: {}", hosts.join(", ")))
            }),
            end: EventDateTime {
                date_time: ends_at,
                time_zone: timezone.clone(),
            },
            start: EventDateTime {
                date_time: starts_at,
                time_zone: timezone,
            },
            summary: m.topic.clone().unwrap_or_else(|| "GOUP meeting".to_string()),
        })
    }
}

/// Date-time shape expected by Google Calendar API.
#[skip_serializing_none]
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct EventDateTime {
    pub date_time: DateTime<Utc>,
    pub time_zone: Option<String>,
}

/// Conference creation data.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ConferenceData {
    pub create_request: ConferenceCreateRequest,
}

/// Conference creation request.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ConferenceCreateRequest {
    pub conference_solution_key: ConferenceSolutionKey,
    pub request_id: String,
}

/// Conference solution key.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ConferenceSolutionKey {
    #[serde(rename = "type")]
    pub conference_type: &'static str,
}

/// Response from Google's OAuth token endpoint.
#[derive(Debug, Deserialize)]
struct TokenResponse {
    access_token: String,
    expires_in: u64,
}

/// Google Calendar event details returned by the client.
#[derive(Debug)]
pub(crate) struct GoogleCalendarEvent {
    pub id: String,
    pub meet_url: Option<String>,
}

impl TryFrom<CalendarEventResponse> for GoogleCalendarEvent {
    type Error = GoogleCalendarClientError;

    fn try_from(response: CalendarEventResponse) -> Result<Self, Self::Error> {
        let meet_url = response.hangout_link.or_else(|| {
            response.conference_data.and_then(|conference_data| {
                conference_data.entry_points.into_iter().find_map(|entry_point| {
                    (entry_point.entry_point_type == "video").then_some(entry_point.uri)
                })
            })
        });

        Ok(Self {
            id: response.id.ok_or_else(|| GoogleCalendarClientError::Client {
                code: 400,
                message: "google calendar event response missing id".to_string(),
            })?,
            meet_url,
        })
    }
}

/// Calendar event response.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CalendarEventResponse {
    conference_data: Option<ConferenceDataResponse>,
    hangout_link: Option<String>,
    id: Option<String>,
}

/// Conference data response.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ConferenceDataResponse {
    #[serde(default)]
    entry_points: Vec<ConferenceEntryPoint>,
}

/// Conference entry point response.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ConferenceEntryPoint {
    entry_point_type: String,
    uri: String,
}

/// Error types from Google Calendar client calls.
#[derive(Debug)]
pub(crate) enum GoogleCalendarClientError {
    /// Non-retryable client errors.
    Client { code: i32, message: String },
    /// Network or connection errors.
    Network(String),
    /// Rate limit exceeded.
    RateLimit { retry_after: Duration },
    /// Server errors.
    Server { code: i32, message: String },
    /// Token fetch error.
    Token(String),
}

impl std::fmt::Display for GoogleCalendarClientError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Client { code, message } => {
                write!(f, "google calendar client error: {code} - {message}")
            }
            Self::Network(msg) => write!(f, "google calendar network error: {msg}"),
            Self::RateLimit { retry_after } => {
                write!(
                    f,
                    "google calendar rate limit exceeded (retry after {}s)",
                    retry_after.as_secs()
                )
            }
            Self::Server { code, message } => {
                write!(f, "google calendar server error: {code} - {message}")
            }
            Self::Token(msg) => write!(f, "google calendar token error: {msg}"),
        }
    }
}

impl std::error::Error for GoogleCalendarClientError {}

impl From<GoogleCalendarClientError> for MeetingProviderError {
    fn from(e: GoogleCalendarClientError) -> Self {
        match e {
            GoogleCalendarClientError::Client { code, message } => {
                if code == GOOGLE_CALENDAR_EVENT_NOT_FOUND {
                    Self::NotFound
                } else {
                    Self::Client(format!("{code}: {message}"))
                }
            }
            GoogleCalendarClientError::Network(msg) => Self::Network(msg),
            GoogleCalendarClientError::RateLimit { retry_after } => Self::RateLimit { retry_after },
            GoogleCalendarClientError::Server { code, message } => {
                Self::Server(format!("{code}: {message}"))
            }
            GoogleCalendarClientError::Token(msg) => Self::Token(msg),
        }
    }
}

impl GoogleCalendarClientError {
    /// Create error from HTTP response status and body.
    async fn from_response(response: reqwest::Response) -> Self {
        let retry_after = response
            .headers()
            .get(reqwest::header::RETRY_AFTER)
            .and_then(|v| v.to_str().ok())
            .and_then(|s| s.parse::<u64>().ok())
            .map_or(Duration::from_mins(1), Duration::from_secs);
        let status = response.status();
        let error: GoogleCalendarErrorEnvelope = response.json().await.unwrap_or_default();
        let code = if error.error.code == 0 {
            i32::from(status.as_u16())
        } else {
            error.error.code
        };
        let message = error.error.message;

        if status == reqwest::StatusCode::TOO_MANY_REQUESTS {
            Self::RateLimit { retry_after }
        } else if status == reqwest::StatusCode::UNAUTHORIZED
            || status == reqwest::StatusCode::FORBIDDEN
        {
            Self::Token(format!("{code} - {message}"))
        } else if status.is_client_error() {
            Self::Client { code, message }
        } else {
            Self::Server { code, message }
        }
    }
}

/// Google Calendar error envelope.
#[derive(Debug, Default, Deserialize)]
struct GoogleCalendarErrorEnvelope {
    #[serde(default)]
    error: GoogleCalendarError,
}

/// Google Calendar error body.
#[derive(Debug, Default, Deserialize)]
struct GoogleCalendarError {
    #[serde(default)]
    code: i32,
    #[serde(default)]
    message: String,
}

/// Google OAuth token error response.
#[derive(Debug, Default, Deserialize)]
struct GoogleTokenErrorResponse {
    #[serde(default)]
    error: String,
    #[serde(default)]
    error_description: String,
}

/// Validate and convert a duration to minutes.
fn duration_minutes(d: std::time::Duration) -> Result<i64, GoogleCalendarClientError> {
    let minutes = i64::try_from(d.as_secs() / 60).unwrap_or(i64::MAX);
    if !(MIN_DURATION_MINUTES..=MAX_DURATION_MINUTES).contains(&minutes) {
        return Err(GoogleCalendarClientError::Client {
            code: 400,
            message: format!("invalid meeting duration: {minutes} minutes"),
        });
    }
    Ok(minutes)
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use chrono::Utc;
    use serde_json::json;

    use crate::services::meetings::Meeting;

    use super::CalendarEventRequest;

    #[test]
    fn create_event_request_can_include_meet_conference_data() {
        let request = CalendarEventRequest::try_from(&Meeting {
            duration: Some(Duration::from_mins(30)),
            starts_at: Some(Utc::now()),
            topic: Some("Demo".to_string()),
            timezone: Some("America/New_York".to_string()),
            ..Default::default()
        })
        .unwrap()
        .with_meet_conference();
        let value = serde_json::to_value(request).unwrap();

        assert_eq!(value["summary"], json!("Demo"));
        assert_eq!(
            value["conferenceData"]["createRequest"]["conferenceSolutionKey"]["type"],
            json!("hangoutsMeet")
        );
        assert!(
            value["conferenceData"]["createRequest"]["requestId"]
                .as_str()
                .is_some_and(|request_id| !request_id.is_empty())
        );
    }
}
