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
            && let Some(zoom_cfg) = &meetings_cfg.zoom
        {
            zoom_cfg.validate()?;
        }

        Ok(())
    }
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
    /// Zoom provider configuration.
    pub zoom: Option<MeetingsZoomConfig>,
}

impl MeetingsConfig {
    /// Check if at least one meetings provider is enabled.
    pub(crate) fn meetings_enabled(&self) -> bool {
        self.zoom.as_ref().is_some_and(|z| z.enabled)
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
    /// Enable Linux Foundation login.
    pub linuxfoundation: bool,
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
    /// Linux Foundation as an OIDC provider.
    LinuxFoundation,
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
