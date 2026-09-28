//! Configuration management for the OCG server.
//!
//! This module handles loading and parsing configuration from multiple sources using
//! Figment. Configuration can be provided via:
//!
//! - YAML configuration file
//! - Environment variables (with OCG_ prefix)

use std::{
    collections::{HashMap, HashSet},
    fmt,
    path::PathBuf,
    time::Duration,
};

use anyhow::{Result, bail};
use figment::{
    Figment,
    providers::{Env, Format, Serialized, Yaml},
};
use garde::rules::email::parse_email;
use ocg_common::config::{DbConfig, LogConfig};
use serde::{Deserialize, Serialize};
use ssi_jwk::{JWK, Params};
use ssi_verification_methods::ed25519_dalek::{SigningKey, VerifyingKey};
use strum::AsRefStr;
use tracing::instrument;

use crate::types::{
    meetings::MeetingProvider,
    payments::{PaymentMode, PaymentProvider},
};

#[cfg(test)]
mod tests;

/// Default connection deadline in seconds for outbound clients.
const DEFAULT_CONNECT_TIMEOUT_SECS: u64 = 10;

/// Default organizer-confirmation window in hours for external payments.
const DEFAULT_EXTERNAL_PAYMENT_WINDOW_HOURS: i32 = 72;

/// Default maximum organizer-confirmation window in hours for external payments.
const DEFAULT_MAX_EXTERNAL_PAYMENT_WINDOW_HOURS: i32 = 336;

/// Default total-operation deadline in seconds for outbound clients.
const DEFAULT_REQUEST_TIMEOUT_SECS: u64 = 30;

/// Default grace period in seconds granted to background workers on shutdown.
const DEFAULT_SHUTDOWN_GRACE_PERIOD_SECS: u64 = 30;

/// Maximum platform fee expressed in basis points (99.99% of the amount).
const MAX_PLATFORM_FEE_BPS: u16 = 9_999;

/// Placeholder used when formatting sensitive configuration values.
const REDACTED_CONFIG_VALUE: &str = "[redacted]";

/// Root configuration structure for the OCG server.
#[derive(Clone, Deserialize, Serialize)]
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

    /// External payments configuration for countries without Stripe Connect.
    pub external_payments: Option<ExternalPaymentsConfig>,
    /// Meetings configuration.
    pub meetings: Option<MeetingsConfig>,
    /// Payments configuration.
    pub payments: Option<PaymentsConfig>,
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
        // Validate database transport security before starting dependent services
        self.db.validate()?;

        // Validate operational bounds owned by the server and email sections
        self.server.validate()?;
        self.email.smtp.validate()?;

        // Require badge signing because public credentials and status lists are always mounted
        let badges_cfg = self
            .server
            .badges
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("server.badges is required"))?;
        badges_cfg.validate()?;

        // Validate optional provider configuration
        if let Some(external_payments_cfg) = &self.external_payments {
            external_payments_cfg.validate()?;
        }

        if let Some(meetings_cfg) = &self.meetings
            && let Some(zoom_cfg) = &meetings_cfg.zoom
        {
            zoom_cfg.validate()?;
        }

        if let Some(payments_cfg) = &self.payments {
            payments_cfg.validate()?;
        }

        Ok(())
    }
}

impl fmt::Debug for Config {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Config")
            .field("db", &REDACTED_CONFIG_VALUE)
            .field("email", &self.email)
            .field("images", &self.images)
            .field("log", &self.log)
            .field("server", &self.server)
            .field("external_payments", &self.external_payments)
            .field("meetings", &self.meetings)
            .field("payments", &self.payments)
            .finish()
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
#[derive(Clone, PartialEq, Deserialize, Serialize)]
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

impl fmt::Debug for ImageStorageConfigS3 {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("ImageStorageConfigS3")
            .field("access_key_id", &self.access_key_id)
            .field("bucket", &self.bucket)
            .field("region", &self.region)
            .field("secret_access_key", &REDACTED_CONFIG_VALUE)
            .field("endpoint", &self.endpoint)
            .field("force_path_style", &self.force_path_style)
            .finish()
    }
}

/// External payments configuration for countries without Stripe Connect.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub(crate) struct ExternalPaymentsConfig {
    /// ISO 3166-1 alpha-2 country codes allowed to enable external payments.
    pub allowed_countries: Vec<String>,

    /// Default organizer-confirmation window in hours when an event omits one.
    #[serde(default = "default_external_payment_window_hours")]
    pub default_payment_window_hours: i32,
    /// Maximum organizer-confirmation window in hours an event may request.
    #[serde(default = "default_max_external_payment_window_hours")]
    pub max_payment_window_hours: i32,
}

impl ExternalPaymentsConfig {
    /// Return allowlisted country codes normalized to uppercase.
    pub(crate) fn allowed_countries_normalized(&self) -> Vec<String> {
        self.allowed_countries
            .iter()
            .map(|country| country.trim().to_ascii_uppercase())
            .collect()
    }

    /// Validate the allowlist and payment-window limits.
    pub(crate) fn validate(&self) -> Result<()> {
        // Reject an empty allowlist because it would look configured while disabling the feature
        if self.allowed_countries.is_empty() {
            bail!("external_payments.allowed_countries cannot be empty");
        }

        // Reject invalid or duplicate ISO 3166-1 alpha-2 country codes
        let mut seen = HashSet::new();
        for country in &self.allowed_countries {
            let normalized = country.trim().to_ascii_uppercase();
            if normalized.len() != 2 || !normalized.bytes().all(|byte| byte.is_ascii_uppercase()) {
                bail!(
                    "external_payments.allowed_countries contains invalid country code '{country}'"
                );
            }
            if !seen.insert(normalized) {
                bail!(
                    "external_payments.allowed_countries contains duplicate country code '{country}'"
                );
            }
        }

        // Reject non-positive windows and a default above the configured maximum
        if self.default_payment_window_hours < 1 {
            bail!("external_payments.default_payment_window_hours must be at least 1");
        }
        if self.max_payment_window_hours < 1 {
            bail!("external_payments.max_payment_window_hours must be at least 1");
        }
        if self.default_payment_window_hours > self.max_payment_window_hours {
            bail!(
                "external_payments.default_payment_window_hours cannot exceed max_payment_window_hours"
            );
        }

        Ok(())
    }
}

/// Meetings configuration (multiple providers supported).
#[derive(Debug, Clone, Default, PartialEq, Deserialize, Serialize)]
pub(crate) struct MeetingsConfig {
    /// Zoom provider configuration.
    pub zoom: Option<MeetingsZoomConfig>,
}

impl MeetingsConfig {
    /// Returns the maximum meeting participants configured per provider.
    pub(crate) fn max_participants_by_provider(&self) -> HashMap<MeetingProvider, i32> {
        let mut max_participants = HashMap::new();
        if let Some(zoom) = &self.zoom {
            max_participants.insert(MeetingProvider::Zoom, zoom.max_participants);
        }
        max_participants
    }

    /// Check if at least one meetings provider is enabled.
    pub(crate) fn meetings_enabled(&self) -> bool {
        self.zoom.as_ref().is_some_and(|z| z.enabled)
    }
}

/// Zoom meetings configuration.
#[derive(Clone, PartialEq, Deserialize, Serialize)]
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

    /// Deadlines applied to Zoom API requests.
    #[serde(default)]
    pub http_client: HttpClientConfig,
}

impl fmt::Debug for MeetingsZoomConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("MeetingsZoomConfig")
            .field("account_id", &self.account_id)
            .field("client_id", &self.client_id)
            .field("client_secret", &REDACTED_CONFIG_VALUE)
            .field("enabled", &self.enabled)
            .field("host_pool_users", &self.host_pool_users)
            .field("max_participants", &self.max_participants)
            .field(
                "max_simultaneous_meetings_per_host",
                &self.max_simultaneous_meetings_per_host,
            )
            .field("webhook_secret_token", &REDACTED_CONFIG_VALUE)
            .field("http_client", &self.http_client)
            .finish()
    }
}

impl MeetingsZoomConfig {
    /// Validate Zoom meetings configuration.
    fn validate(&self) -> Result<()> {
        // Skip validation when Zoom meetings are disabled
        if !self.enabled {
            return Ok(());
        }

        // Validate the deadlines applied to Zoom API requests
        self.http_client.validate("meetings.zoom.http_client")?;

        // Validate max overlapping meetings allowed for each host
        if self.max_simultaneous_meetings_per_host < 1 {
            bail!("meetings.zoom.max_simultaneous_meetings_per_host must be >= 1");
        }

        // Validate that the user pool contains valid, unique email addresses
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

/// Payments configuration for the single active provider.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(tag = "provider", rename_all = "snake_case")]
pub(crate) enum PaymentsConfig {
    /// Stripe payments configuration.
    Stripe(PaymentsStripeConfig),
}

impl PaymentsConfig {
    /// Return the platform fee in basis points applied to paid purchases.
    pub(crate) fn platform_fee_bps(&self) -> u16 {
        match self {
            Self::Stripe(cfg) => cfg.platform_fee_bps,
        }
    }

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
#[derive(Clone, PartialEq, Deserialize, Serialize)]
pub(crate) struct PaymentsStripeConfig {
    /// Stripe Connect webhook secret used for connected-account events.
    pub connected_webhook_secret: String,
    /// Mode used for the configured credentials.
    ///
    /// Use `test` with Stripe test credentials during development.
    /// Use `live` only for real payments in production environments.
    pub mode: PaymentMode,
    /// Stripe secret key used by the backend.
    pub secret_key: String,
    /// Public-preview API version used for Tax for ticket sales.
    pub ticket_tax_api_version: String,
    /// Stripe webhook secret used for signature verification.
    pub webhook_secret: String,

    /// Deadlines applied to Stripe API requests.
    #[serde(default)]
    pub http_client: HttpClientConfig,
    /// Platform fee in basis points deducted from the group's proceeds on
    /// each paid purchase (e.g. 250 = 2.5%). Defaults to 0 (no fee).
    #[serde(default)]
    pub platform_fee_bps: u16,
}

impl fmt::Debug for PaymentsStripeConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("PaymentsStripeConfig")
            .field("connected_webhook_secret", &REDACTED_CONFIG_VALUE)
            .field("mode", &self.mode)
            .field("secret_key", &REDACTED_CONFIG_VALUE)
            .field("ticket_tax_api_version", &self.ticket_tax_api_version)
            .field("webhook_secret", &REDACTED_CONFIG_VALUE)
            .field("http_client", &self.http_client)
            .field("platform_fee_bps", &self.platform_fee_bps)
            .finish()
    }
}

impl PaymentsStripeConfig {
    /// Validate Stripe payments configuration.
    fn validate(&self) -> Result<()> {
        // Validate the deadlines applied to Stripe API requests
        self.http_client.validate("payments.http_client")?;

        if self.platform_fee_bps > MAX_PLATFORM_FEE_BPS {
            bail!("payments.platform_fee_bps cannot exceed {MAX_PLATFORM_FEE_BPS}");
        }

        if self.connected_webhook_secret.trim().is_empty() {
            bail!("payments.connected_webhook_secret cannot be empty");
        }

        if self.secret_key.trim().is_empty() {
            bail!("payments.secret_key cannot be empty");
        }

        if self.ticket_tax_api_version.trim().is_empty() {
            bail!("payments.ticket_tax_api_version cannot be empty");
        }

        if self.webhook_secret.trim().is_empty() {
            bail!("payments.webhook_secret cannot be empty");
        }

        Ok(())
    }
}

/// SMTP server configuration.
#[derive(Clone, PartialEq, Deserialize, Serialize)]
pub(crate) struct SmtpConfig {
    /// SMTP server hostname.
    pub host: String,
    /// SMTP password.
    pub password: String,
    /// SMTP server port.
    pub port: u16,
    /// SMTP username.
    pub username: String,

    /// Deadline in seconds for establishing the SMTP connection.
    #[serde(default = "default_connect_timeout_secs")]
    pub connect_timeout_secs: u64,
    /// Deadline in seconds for one complete delivery attempt.
    #[serde(default = "default_request_timeout_secs")]
    pub send_timeout_secs: u64,
}

impl fmt::Debug for SmtpConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("SmtpConfig")
            .field("host", &self.host)
            .field("password", &REDACTED_CONFIG_VALUE)
            .field("port", &self.port)
            .field("username", &self.username)
            .field("connect_timeout_secs", &self.connect_timeout_secs)
            .field("send_timeout_secs", &self.send_timeout_secs)
            .finish()
    }
}

impl SmtpConfig {
    /// Returns the deadline for establishing the SMTP connection.
    pub(crate) fn connect_timeout(&self) -> Duration {
        Duration::from_secs(self.connect_timeout_secs)
    }

    /// Returns the deadline for one complete delivery attempt.
    pub(crate) fn send_timeout(&self) -> Duration {
        Duration::from_secs(self.send_timeout_secs)
    }

    /// Validate SMTP delivery deadlines.
    fn validate(&self) -> Result<()> {
        if self.connect_timeout_secs == 0 {
            bail!("email.smtp.connect_timeout_secs must be >= 1");
        }

        if self.send_timeout_secs == 0 {
            bail!("email.smtp.send_timeout_secs must be >= 1");
        }

        Ok(())
    }
}

/// HTTP server configuration settings.
#[derive(Debug, Clone, Default, PartialEq, Deserialize, Serialize)]
pub(crate) struct HttpServerConfig {
    /// The address the HTTP server will listen on.
    pub addr: String,
    /// Base URL for the server.
    pub base_url: String,
    /// Login options configuration.
    pub login: LoginOptions,
    /// `OAuth2` providers configuration.
    pub oauth2: OAuth2Config,
    /// OIDC providers configuration.
    pub oidc: OidcConfig,

    /// Allows ordinary stored images to be embedded by other origins.
    #[serde(default)]
    pub allow_image_hotlinking: bool,
    /// Badge credential signing and verification configuration required at startup.
    pub badges: Option<BadgesConfig>,
    /// Optional cookie configuration.
    pub cookie: Option<CookieConfig>,
    /// Deadlines applied to login provider requests (`OAuth2`, OIDC, GitHub).
    #[serde(default)]
    pub http_client: HttpClientConfig,
    /// Maximum CPU-heavy tasks (password hashing) running at once.
    ///
    /// Defaults to the available parallelism of the host.
    pub max_blocking_concurrency: Option<usize>,
    /// Optional list of hostnames that should redirect to `base_url`.
    pub redirect_hosts: Option<Vec<String>>,
    /// Grace period in seconds granted to background workers on shutdown.
    #[serde(default = "default_shutdown_grace_period_secs")]
    pub shutdown_grace_period_secs: u64,
}

impl HttpServerConfig {
    /// Returns the maximum number of CPU-heavy tasks allowed to run at once.
    pub(crate) fn max_blocking_concurrency(&self) -> usize {
        self.max_blocking_concurrency.unwrap_or_else(|| {
            std::thread::available_parallelism().map_or(1, std::num::NonZero::get)
        })
    }

    /// Returns the grace period granted to background workers on shutdown.
    pub(crate) fn shutdown_grace_period(&self) -> Duration {
        Duration::from_secs(self.shutdown_grace_period_secs)
    }

    /// Validate server-owned operational bounds.
    fn validate(&self) -> Result<()> {
        // Validate the deadlines applied to login provider requests
        self.http_client.validate("server.http_client")?;

        // Reject a bound that would never let CPU-heavy work run
        if self.max_blocking_concurrency == Some(0) {
            bail!("server.max_blocking_concurrency must be >= 1");
        }

        Ok(())
    }
}

/// Deadlines applied to an outbound HTTP client.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub(crate) struct HttpClientConfig {
    /// Deadline in seconds for establishing a connection.
    #[serde(default = "default_connect_timeout_secs")]
    pub connect_timeout_secs: u64,
    /// Deadline in seconds for one complete request, including the response body.
    #[serde(default = "default_request_timeout_secs")]
    pub request_timeout_secs: u64,
}

impl HttpClientConfig {
    /// Returns the deadline for establishing a connection.
    pub(crate) fn connect_timeout(&self) -> Duration {
        Duration::from_secs(self.connect_timeout_secs)
    }

    /// Returns the deadline for one complete request.
    pub(crate) fn request_timeout(&self) -> Duration {
        Duration::from_secs(self.request_timeout_secs)
    }

    /// Validate the deadlines under the named configuration section.
    fn validate(&self, section: &str) -> Result<()> {
        if self.connect_timeout_secs == 0 {
            bail!("{section}.connect_timeout_secs must be >= 1");
        }

        if self.request_timeout_secs == 0 {
            bail!("{section}.request_timeout_secs must be >= 1");
        }

        Ok(())
    }
}

impl Default for HttpClientConfig {
    fn default() -> Self {
        Self {
            connect_timeout_secs: DEFAULT_CONNECT_TIMEOUT_SECS,
            request_timeout_secs: DEFAULT_REQUEST_TIMEOUT_SECS,
        }
    }
}

/// Badge credential signing and verification configuration.
#[derive(Clone, PartialEq, Deserialize, Serialize)]
pub(crate) struct BadgesConfig {
    /// Active private key used to sign new credentials.
    pub signing_key: BadgeSigningKeyConfig,

    /// Previously published public keys retained for credential verification.
    #[serde(default)]
    pub verification_keys: Vec<BadgeVerificationKeyConfig>,
}

impl BadgesConfig {
    /// Validate key identifiers and Ed25519 key material.
    fn validate(&self) -> Result<()> {
        // Validate the active private signing key
        let mut key_ids = HashSet::new();
        let signing_key = &self.signing_key;
        validate_badge_key_id(&signing_key.key_id)?;
        validate_ed25519_key(&signing_key.private_jwk, true)?;
        key_ids.insert(&signing_key.key_id);

        // Validate retained public keys and reject identifier collisions
        for verification_key in &self.verification_keys {
            validate_badge_key_id(&verification_key.key_id)?;
            validate_ed25519_key(&verification_key.public_jwk, false)?;
            if !key_ids.insert(&verification_key.key_id) {
                bail!("server.badges contains duplicate key identifiers");
            }
        }

        Ok(())
    }
}

impl fmt::Debug for BadgesConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("BadgesConfig")
            .field("signing_key", &self.signing_key)
            .field("verification_keys", &self.verification_keys)
            .finish()
    }
}

/// Active Ed25519 signing key configuration.
#[derive(Clone, PartialEq, Deserialize, Serialize)]
pub(crate) struct BadgeSigningKeyConfig {
    /// Stable URL-safe key identifier.
    pub key_id: String,
    /// Private Ed25519 JWK.
    pub private_jwk: JWK,
}

impl fmt::Debug for BadgeSigningKeyConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("BadgeSigningKeyConfig")
            .field("key_id", &self.key_id)
            .field("private_jwk", &REDACTED_CONFIG_VALUE)
            .finish()
    }
}

/// Retained Ed25519 verification key configuration.
#[derive(Clone, PartialEq, Deserialize, Serialize)]
pub(crate) struct BadgeVerificationKeyConfig {
    /// Stable URL-safe key identifier.
    pub key_id: String,
    /// Public Ed25519 JWK.
    pub public_jwk: JWK,
}

impl fmt::Debug for BadgeVerificationKeyConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("BadgeVerificationKeyConfig")
            .field("key_id", &self.key_id)
            .field("public_jwk", &REDACTED_CONFIG_VALUE)
            .finish()
    }
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
#[derive(AsRefStr, Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub(crate) enum OAuth2Provider {
    /// GitHub as an `OAuth2` provider.
    #[strum(serialize = "github")]
    GitHub,
}

/// `OAuth2` provider configuration.
#[derive(Clone, PartialEq, Deserialize, Serialize)]
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

impl fmt::Debug for OAuth2ProviderConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("OAuth2ProviderConfig")
            .field("auth_url", &self.auth_url)
            .field("client_id", &self.client_id)
            .field("client_secret", &REDACTED_CONFIG_VALUE)
            .field("redirect_uri", &self.redirect_uri)
            .field("scopes", &self.scopes)
            .field("token_url", &self.token_url)
            .finish()
    }
}

/// Type alias for the OIDC configuration section.
pub(crate) type OidcConfig = HashMap<OidcProvider, OidcProviderConfig>;

/// Supported OIDC providers.
#[derive(AsRefStr, Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub(crate) enum OidcProvider {
    /// Linux Foundation as an OIDC provider.
    #[strum(serialize = "linuxfoundation")]
    LinuxFoundation,
}

/// OIDC provider configuration.
#[derive(Clone, PartialEq, Deserialize, Serialize)]
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

impl fmt::Debug for OidcProviderConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("OidcProviderConfig")
            .field("client_id", &self.client_id)
            .field("client_secret", &REDACTED_CONFIG_VALUE)
            .field("issuer_url", &self.issuer_url)
            .field("redirect_uri", &self.redirect_uri)
            .field("scopes", &self.scopes)
            .finish()
    }
}

// Helpers.

/// Default connection deadline used when the config omits it.
fn default_connect_timeout_secs() -> u64 {
    DEFAULT_CONNECT_TIMEOUT_SECS
}

/// Default organizer-confirmation window used when the config omits it.
fn default_external_payment_window_hours() -> i32 {
    DEFAULT_EXTERNAL_PAYMENT_WINDOW_HOURS
}

/// Default maximum organizer-confirmation window used when the config omits it.
fn default_max_external_payment_window_hours() -> i32 {
    DEFAULT_MAX_EXTERNAL_PAYMENT_WINDOW_HOURS
}

/// Default total-operation deadline used when the config omits it.
fn default_request_timeout_secs() -> u64 {
    DEFAULT_REQUEST_TIMEOUT_SECS
}

/// Default shutdown grace period used when the config omits it.
fn default_shutdown_grace_period_secs() -> u64 {
    DEFAULT_SHUTDOWN_GRACE_PERIOD_SECS
}

/// Validate a stable badge verification key identifier.
fn validate_badge_key_id(key_id: &str) -> Result<()> {
    // Check length, allowed characters, and identifier boundaries
    let valid = (1..=64).contains(&key_id.len())
        && key_id
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
        && key_id.as_bytes().first().is_some_and(u8::is_ascii_alphanumeric)
        && key_id.as_bytes().last().is_some_and(u8::is_ascii_alphanumeric);

    // Reject identifiers that cannot be used in stable public key URLs
    if !valid {
        bail!(
            "server.badges key identifiers must be 1-64 lowercase URL-safe characters and start and end with a letter or digit"
        );
    }

    Ok(())
}

/// Validate an Ed25519 JWK without including key material in errors.
fn validate_ed25519_key(key: &JWK, require_private: bool) -> Result<()> {
    // Require the expected JWK parameter family
    let Params::OKP(params) = &key.params else {
        bail!("server.badges keys must be Ed25519 JWKs");
    };

    // Validate the public key curve and material
    if params.curve != "Ed25519" || params.public_key.0.len() != 32 {
        bail!("server.badges keys must be Ed25519 JWKs");
    }
    let public_key: [u8; 32] = params
        .public_key
        .0
        .as_slice()
        .try_into()
        .map_err(|_| anyhow::anyhow!("server.badges keys must be Ed25519 JWKs"))?;
    let public_key = VerifyingKey::from_bytes(&public_key)
        .map_err(|_| anyhow::anyhow!("server.badges keys must be Ed25519 JWKs"))?;

    // Require private key material for signing keys
    if require_private && params.private_key.as_ref().is_none_or(|key| key.0.len() != 32) {
        bail!("server.badges signing key must contain an Ed25519 private key");
    }

    // Verify any supplied private key matches the public key
    if let Some(private_key) = &params.private_key {
        let private_key: [u8; 32] = private_key.0.as_slice().try_into().map_err(|_| {
            anyhow::anyhow!("server.badges signing key must contain an Ed25519 private key")
        })?;
        if SigningKey::from_bytes(&private_key).verifying_key() != public_key {
            bail!("server.badges signing key public and private material must match");
        }
    }

    // Reject private key material from verification-only keys
    if !require_private && params.private_key.is_some() {
        bail!("server.badges verification keys must contain public material only");
    }

    Ok(())
}
