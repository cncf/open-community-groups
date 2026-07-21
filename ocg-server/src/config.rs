//! Configuration management for the OCG server.
//!
//! This module handles loading and parsing configuration from multiple sources using
//! Figment. Configuration can be provided via:
//!
//! - YAML configuration file
//! - Environment variables (with OCG_ prefix)

use std::{
    collections::{HashMap, HashSet},
    path::PathBuf,
};

use anyhow::{Result, bail};
use deadpool_postgres::Config as DbConfig;
use figment::{
    Figment,
    providers::{Env, Format, Serialized, Yaml},
};
use garde::rules::email::parse_email;
use serde::{Deserialize, Serialize};
use tracing::instrument;

use crate::types::payments::{PaymentMode, PaymentProvider};

/// Root configuration structure for the OCG server.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub(crate) struct Config {
    /// Database configuration.
    pub db: DbConfig,
    /// Email configuration.
    pub email: EmailConfig,
    /// Image storage configuration.
    pub images: ImageStorageConfig,
    /// Logging configuration.
    pub log: LogConfig,
    /// HTTP server configuration.
    pub server: HttpServerConfig,

    /// Meetings configuration.
    pub meetings: Option<MeetingsConfig>,
    /// Payments configuration.
    pub payments: Option<PaymentsConfig>,
    /// Recording publishing configuration.
    pub recording_publishing: Option<RecordingPublishingConfig>,
    /// External partner integrations.
    pub integrations: Option<IntegrationsConfig>,
}

impl Config {
    /// Creates a new Config instance from available configuration sources.
    ///
    /// Configuration is loaded in the following order (later sources override):
    ///
    /// 1. Default values
    /// 2. Optional YAML configuration file
    /// 3. Environment variables with OCG_ prefix
    #[instrument(err)]
    pub(crate) fn new(config_file: Option<&PathBuf>) -> Result<Self> {
        let mut figment = Figment::new()
            .merge(Serialized::default("log.format", "json"))
            .merge(Serialized::default("images.provider", "db"))
            .merge(Serialized::default("server.addr", "127.0.0.1:9000"));

        if let Some(config_file) = config_file {
            figment = figment.merge(Yaml::file(config_file));
        }

        let cfg: Self = figment
            .merge(Env::prefixed("OCG_").split("__"))
            .extract()
            .map_err(anyhow::Error::from)?;

        cfg.validate()?;

        Ok(cfg)
    }

    /// Validate configuration consistency after loading from all sources.
    fn validate(&self) -> Result<()> {
        if let Some(meetings_cfg) = &self.meetings
            && let Some(google_cfg) = &meetings_cfg.google_meet
        {
            google_cfg.validate()?;
        }

        if let Some(meetings_cfg) = &self.meetings
            && let Some(zoom_cfg) = &meetings_cfg.zoom
        {
            zoom_cfg.validate()?;
        }

        if let Some(payments_cfg) = &self.payments {
            payments_cfg.validate()?;
        }

        if let Some(recording_publishing_cfg) = &self.recording_publishing {
            recording_publishing_cfg.validate()?;
        }

        if let Some(integrations_cfg) = &self.integrations {
            integrations_cfg.validate()?;
        }

        Ok(())
    }
}

/// Configuration for external partner integrations.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub(crate) struct IntegrationsConfig {
    /// You.com event discovery configuration.
    pub you_com: Option<YouComConfig>,
}

impl IntegrationsConfig {
    fn validate(&self) -> Result<()> {
        if let Some(you_com) = &self.you_com {
            you_com.validate()?;
        }
        Ok(())
    }
}

/// Configuration for You.com event discovery.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub(crate) struct YouComConfig {
    /// Enables the event discovery worker.
    #[serde(default)]
    pub enabled: bool,
    /// Secret API key. Set this through `OCG_INTEGRATIONS__YOU_COM__API_KEY`.
    pub api_key: String,
    /// Search endpoint, allowing API-version changes without source changes.
    #[serde(default = "default_you_com_search_url")]
    pub search_url: String,
    /// IANA timezone used to schedule the daily discovery run.
    #[serde(default = "default_baku_timezone")]
    pub schedule_timezone: String,
    /// Hour of the daily discovery run in the configured timezone.
    #[serde(default = "default_baku_schedule_hour")]
    pub schedule_hour: u8,
}

impl YouComConfig {
    fn validate(&self) -> Result<()> {
        if self.enabled && self.api_key.trim().is_empty() {
            bail!("integrations.you_com.api_key is required when You.com is enabled");
        }
        if self.schedule_hour > 23 {
            bail!("integrations.you_com.schedule_hour must be between 0 and 23");
        }
        self.search_url
            .parse::<reqwest::Url>()
            .map_err(|err| anyhow::anyhow!("invalid integrations.you_com.search_url: {err}"))?;
        self.schedule_timezone.parse::<chrono_tz::Tz>().map_err(|err| {
            anyhow::anyhow!("invalid integrations.you_com.schedule_timezone: {err}")
        })?;
        Ok(())
    }
}

fn default_you_com_search_url() -> String {
    "https://api.you.com/v1/search".into()
}

fn default_baku_timezone() -> String {
    "Asia/Baku".into()
}

const fn default_baku_schedule_hour() -> u8 {
    9
}

/// Email configuration.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub(crate) struct EmailConfig {
    /// Sender email address.
    pub from_address: String,
    /// Sender display name.
    pub from_name: String,
    /// SMTP server configuration.
    pub smtp: SmtpConfig,

    /// Optional whitelist of allowed recipient email addresses for
    /// development environments. If not present, all recipients are
    /// allowed. If present and empty, none are allowed.
    pub rcpts_whitelist: Option<Vec<String>>,
}

/// Image storage configuration.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(tag = "provider", rename_all = "snake_case")]
pub(crate) enum ImageStorageConfig {
    /// Store images within the main `PostgreSQL` database.
    Db,
    /// Store images on an S3-compatible object storage service.
    S3(ImageStorageConfigS3),
}

/// Configuration for S3-compatible image storage providers.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub(crate) struct ImageStorageConfigS3 {
    /// Access key identifier used for authentication.
    pub access_key_id: String,
    /// Bucket name where images will be stored.
    pub bucket: String,
    /// Region used for the S3-compatible service.
    pub region: String,
    /// Secret access key used for authentication.
    pub secret_access_key: String,

    /// Optional custom endpoint to support non-AWS providers.
    pub endpoint: Option<String>,
    /// Use path-style requests for compatibility with certain providers.
    pub force_path_style: Option<bool>,
}

/// Meetings configuration (multiple providers supported).
#[derive(Debug, Clone, Default, PartialEq, Deserialize, Serialize)]
pub(crate) struct MeetingsConfig {
    /// Google Meet provider configuration.
    pub google_meet: Option<MeetingsGoogleMeetConfig>,
    /// Zoom provider configuration.
    pub zoom: Option<MeetingsZoomConfig>,
}

impl MeetingsConfig {
    /// Check if at least one meetings provider is enabled.
    pub(crate) fn meetings_enabled(&self) -> bool {
        self.zoom.as_ref().is_some_and(|z| z.enabled)
            || self.google_meet.as_ref().is_some_and(|g| g.enabled)
    }
}

/// Google Meet configuration.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub(crate) struct MeetingsGoogleMeetConfig {
    /// Google Calendar identifier where events with Meet links are created.
    pub calendar_id: String,
    /// OAuth client identifier.
    pub client_id: String,
    /// OAuth client secret.
    pub client_secret: String,
    /// Whether this provider is enabled.
    pub enabled: bool,
    /// Maximum number of participants allowed in a meeting.
    pub max_participants: i32,
    /// OAuth refresh token for the admin calendar account.
    pub refresh_token: String,
}

impl MeetingsGoogleMeetConfig {
    /// Validate Google Meet configuration.
    fn validate(&self) -> Result<()> {
        if !self.enabled {
            return Ok(());
        }

        if self.calendar_id.trim().is_empty() {
            bail!("meetings.google_meet.calendar_id cannot be empty when google_meet is enabled");
        }

        if self.client_id.trim().is_empty() {
            bail!("meetings.google_meet.client_id cannot be empty when google_meet is enabled");
        }

        if self.client_secret.trim().is_empty() {
            bail!("meetings.google_meet.client_secret cannot be empty when google_meet is enabled");
        }

        if self.refresh_token.trim().is_empty() {
            bail!("meetings.google_meet.refresh_token cannot be empty when google_meet is enabled");
        }

        if self.max_participants < 1 {
            bail!("meetings.google_meet.max_participants must be >= 1");
        }

        Ok(())
    }
}

/// Zoom meetings configuration.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub(crate) struct MeetingsZoomConfig {
    /// Zoom account identifier.
    pub account_id: String,
    /// OAuth client identifier.
    pub client_id: String,
    /// OAuth client secret.
    pub client_secret: String,
    /// Whether this provider is enabled.
    pub enabled: bool,
    /// Pool of Zoom users used as meeting hosts.
    pub host_pool_users: Vec<String>,
    /// Maximum number of participants allowed in a meeting (Zoom plan limit).
    pub max_participants: i32,
    /// Maximum overlapping meetings allowed for each Zoom host user.
    pub max_simultaneous_meetings_per_host: i32,
    /// Webhook secret token for signature verification.
    pub webhook_secret_token: String,
}

impl MeetingsZoomConfig {
    /// Validate Zoom meetings configuration.
    fn validate(&self) -> Result<()> {
        // If Zoom meetings are not enabled, skip validation.
        if !self.enabled {
            return Ok(());
        }

        // Validate max overlapping meetings allowed for each host.
        if self.max_simultaneous_meetings_per_host < 1 {
            bail!("meetings.zoom.max_simultaneous_meetings_per_host must be >= 1");
        }

        // Validate that the user pool is not empty and contains valid, unique email addresses.
        let mut seen = HashSet::new();
        if self.host_pool_users.is_empty() {
            bail!("meetings.zoom.host_pool_users cannot be empty when zoom is enabled");
        }
        for email in &self.host_pool_users {
            if email.trim().is_empty() {
                bail!("meetings.zoom.host_pool_users cannot contain empty values");
            }

            parse_email(email).map_err(|err| {
                anyhow::anyhow!("meetings.zoom.host_pool_users has invalid email '{email}': {err}")
            })?;

            let normalized = email.to_lowercase();
            if !seen.insert(normalized) {
                bail!("meetings.zoom.host_pool_users contains duplicate email '{email}'");
            }
        }

        Ok(())
    }
}

/// Recording publishing configuration.
#[derive(Debug, Clone, Default, PartialEq, Deserialize, Serialize)]
pub(crate) struct RecordingPublishingConfig {
    /// `YouTube` publishing configuration.
    pub youtube: Option<RecordingPublishingYouTubeConfig>,
}

impl RecordingPublishingConfig {
    /// Validate recording publishing configuration.
    fn validate(&self) -> Result<()> {
        if let Some(youtube_cfg) = &self.youtube {
            youtube_cfg.validate()?;
        }

        Ok(())
    }
}

/// `YouTube` video visibility.
#[derive(Debug, Clone, Copy, Default, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub(crate) enum YouTubeVideoVisibility {
    /// Video is visible only to the channel owner.
    Private,
    /// Video is visible only to people with the link.
    #[default]
    Unlisted,
    /// Video is visible publicly on the channel.
    Public,
}

impl std::fmt::Display for YouTubeVideoVisibility {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Private => write!(f, "private"),
            Self::Unlisted => write!(f, "unlisted"),
            Self::Public => write!(f, "public"),
        }
    }
}

/// `YouTube` recording publishing configuration.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub(crate) struct RecordingPublishingYouTubeConfig {
    /// OAuth client identifier.
    pub client_id: String,
    /// OAuth client secret.
    pub client_secret: String,
    /// Optional Google Drive folder ID to limit recording searches.
    pub drive_folder_id: Option<String>,
    /// Whether `YouTube` auto-publishing is enabled.
    pub enabled: bool,
    /// Minutes after meeting end before checking for a recording.
    pub publish_delay_minutes: i64,
    /// Minutes to wait before checking again when no recording is found.
    pub retry_delay_minutes: i64,
    /// OAuth refresh token with Drive read and `YouTube` upload scopes.
    pub refresh_token: String,
    /// Visibility for uploaded videos.
    pub visibility: YouTubeVideoVisibility,
}

impl RecordingPublishingYouTubeConfig {
    /// Validate `YouTube` publishing configuration.
    fn validate(&self) -> Result<()> {
        if !self.enabled {
            return Ok(());
        }

        if self.client_id.trim().is_empty() {
            bail!(
                "recording_publishing.youtube.client_id cannot be empty when youtube publishing is enabled"
            );
        }

        if self.client_secret.trim().is_empty() {
            bail!(
                "recording_publishing.youtube.client_secret cannot be empty when youtube publishing is enabled"
            );
        }

        if self.refresh_token.trim().is_empty() {
            bail!(
                "recording_publishing.youtube.refresh_token cannot be empty when youtube publishing is enabled"
            );
        }

        if let Some(drive_folder_id) = &self.drive_folder_id
            && drive_folder_id.trim().is_empty()
        {
            bail!("recording_publishing.youtube.drive_folder_id cannot be empty when provided");
        }

        if self.publish_delay_minutes < 0 {
            bail!("recording_publishing.youtube.publish_delay_minutes must be >= 0");
        }

        if self.retry_delay_minutes < 1 {
            bail!("recording_publishing.youtube.retry_delay_minutes must be >= 1");
        }

        Ok(())
    }
}

/// Payments configuration for the single active provider.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(tag = "provider", rename_all = "snake_case")]
pub(crate) enum PaymentsConfig {
    /// Stripe payments configuration.
    Stripe(PaymentsStripeConfig),
}

impl PaymentsConfig {
    /// Return the configured payments provider.
    pub(crate) fn provider(&self) -> PaymentProvider {
        match self {
            Self::Stripe(_) => PaymentProvider::Stripe,
        }
    }

    /// Validate the configured payments provider.
    fn validate(&self) -> Result<()> {
        match self {
            Self::Stripe(cfg) => cfg.validate(),
        }
    }
}

/// Stripe payments configuration.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub(crate) struct PaymentsStripeConfig {
    /// Mode used for the configured keys.
    ///
    /// Use `test` with Stripe test keys and webhook secret during development.
    /// Use `live` only for real payments in production environments.
    pub mode: PaymentMode,
    /// Stripe publishable key used by the frontend.
    pub publishable_key: String,
    /// Stripe secret key used by the backend.
    pub secret_key: String,
    /// Stripe webhook secret used for signature verification.
    pub webhook_secret: String,
}

impl PaymentsStripeConfig {
    /// Validate Stripe payments configuration.
    fn validate(&self) -> Result<()> {
        if self.publishable_key.trim().is_empty() {
            bail!("payments.publishable_key cannot be empty");
        }

        if self.secret_key.trim().is_empty() {
            bail!("payments.secret_key cannot be empty");
        }

        if self.webhook_secret.trim().is_empty() {
            bail!("payments.webhook_secret cannot be empty");
        }

        Ok(())
    }
}

/// SMTP server configuration.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub(crate) struct SmtpConfig {
    /// SMTP server hostname.
    pub host: String,
    /// SMTP server port.
    pub port: u16,
    /// SMTP username.
    pub username: String,
    /// SMTP password.
    pub password: String,
}

/// Logging configuration.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub(crate) struct LogConfig {
    /// Log output format.
    pub format: LogFormat,
}

/// Supported log output formats.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum LogFormat {
    /// JSON log format.
    Json,
    /// Human-readable log format.
    Pretty,
}

/// HTTP server configuration settings.
#[derive(Debug, Clone, Default, PartialEq, Deserialize, Serialize)]
pub(crate) struct HttpServerConfig {
    /// The address the HTTP server will listen on.
    pub addr: String,
    /// Base URL for the server.
    pub base_url: String,
    /// Disable referer header validation for image endpoints.
    pub disable_referer_checks: bool,
    /// Login options configuration.
    pub login: LoginOptions,
    /// `OAuth2` providers configuration.
    pub oauth2: OAuth2Config,
    /// OIDC providers configuration.
    pub oidc: OidcConfig,

    /// Optional cookie configuration.
    pub cookie: Option<CookieConfig>,
    /// Optional list of hostnames that should redirect to `base_url`.
    pub redirect_hosts: Option<Vec<String>>,
}

/// Cookie settings configuration.
#[derive(Debug, Clone, Default, PartialEq, Deserialize, Serialize)]
pub(crate) struct CookieConfig {
    /// Whether cookies should be secure (HTTPS only).
    pub secure: Option<bool>,
}

/// Login options enabled for the server.
#[derive(Debug, Clone, Default, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub(crate) struct LoginOptions {
    /// Enable email login.
    pub email: bool,
    /// Enable GitHub login.
    pub github: bool,
    /// Enable `LinkedIn` login.
    pub linkedin: bool,
}

/// Type alias for the `OAuth2` configuration section.
pub(crate) type OAuth2Config = HashMap<OAuth2Provider, OAuth2ProviderConfig>;

/// Supported `OAuth2` providers.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub(crate) enum OAuth2Provider {
    /// GitHub as an `OAuth2` provider.
    GitHub,
}

/// `OAuth2` provider configuration.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub(crate) struct OAuth2ProviderConfig {
    /// Authorization endpoint URL.
    pub auth_url: String,
    /// `OAuth2` client ID.
    pub client_id: String,
    /// `OAuth2` client secret.
    pub client_secret: String,
    /// Redirect URI after authentication.
    pub redirect_uri: String,
    /// Scopes requested from the provider.
    pub scopes: Vec<String>,
    /// Token endpoint URL.
    pub token_url: String,
}

/// Type alias for the OIDC configuration section.
pub(crate) type OidcConfig = HashMap<OidcProvider, OidcProviderConfig>;

/// Supported OIDC providers.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub(crate) enum OidcProvider {
    /// `LinkedIn` as an OIDC provider.
    LinkedIn,
}

/// OIDC provider configuration.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub(crate) struct OidcProviderConfig {
    /// OIDC client ID.
    pub client_id: String,
    /// OIDC client secret.
    pub client_secret: String,
    /// OIDC issuer URL.
    pub issuer_url: String,
    /// Redirect URI after authentication.
    pub redirect_uri: String,
    /// Scopes requested from the provider.
    pub scopes: Vec<String>,
}

#[cfg(test)]
mod tests {
    use super::{RecordingPublishingYouTubeConfig, YouTubeVideoVisibility};

    #[test]
    fn youtube_publishing_validation_skips_disabled_config() {
        let cfg = RecordingPublishingYouTubeConfig {
            client_id: String::new(),
            client_secret: String::new(),
            drive_folder_id: None,
            enabled: false,
            publish_delay_minutes: 30,
            refresh_token: String::new(),
            retry_delay_minutes: 15,
            visibility: YouTubeVideoVisibility::Unlisted,
        };

        assert!(cfg.validate().is_ok());
    }

    #[test]
    fn youtube_publishing_validation_requires_credentials_when_enabled() {
        let cfg = RecordingPublishingYouTubeConfig {
            client_id: String::new(),
            client_secret: "secret".to_string(),
            drive_folder_id: None,
            enabled: true,
            publish_delay_minutes: 30,
            refresh_token: "refresh".to_string(),
            retry_delay_minutes: 15,
            visibility: YouTubeVideoVisibility::Unlisted,
        };

        assert!(cfg.validate().is_err());
    }
}
