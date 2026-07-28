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

use crate::types::payments::{PaymentMode, PaymentProvider};

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

        // Require badge signing because public credentials and status lists are always mounted
        let badges_cfg = self
            .server
            .badges
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("server.badges is required"))?;
        badges_cfg.validate()?;

        // Validate optional provider configuration
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

impl fmt::Debug for PaymentsStripeConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("PaymentsStripeConfig")
            .field("mode", &self.mode)
            .field("publishable_key", &self.publishable_key)
            .field("secret_key", &REDACTED_CONFIG_VALUE)
            .field("webhook_secret", &REDACTED_CONFIG_VALUE)
            .finish()
    }
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
}

impl fmt::Debug for SmtpConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("SmtpConfig")
            .field("host", &self.host)
            .field("password", &REDACTED_CONFIG_VALUE)
            .field("port", &self.port)
            .field("username", &self.username)
            .finish()
    }
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

    /// Badge credential signing and verification configuration required at startup.
    pub badges: Option<BadgesConfig>,
    /// Optional cookie configuration.
    pub cookie: Option<CookieConfig>,
    /// Optional list of hostnames that should redirect to `base_url`.
    pub redirect_hosts: Option<Vec<String>>,
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

#[cfg(test)]
mod tests {
    use deadpool_postgres::Config as DeadpoolDbConfig;
    use ocg_common::config::LogFormat;

    use super::*;

    #[test]
    fn test_badges_config_rejects_invalid_keys() {
        // Setup invalid identifiers, mismatched material, and duplicate identifiers
        let private_jwk = JWK::generate_ed25519().unwrap();
        let mut mismatched = private_jwk.clone();
        let Params::OKP(params) = &mut mismatched.params else {
            unreachable!();
        };
        params.public_key.0[0] ^= 1;
        let public_jwk = private_jwk.to_public();

        let invalid_id = BadgesConfig {
            signing_key: BadgeSigningKeyConfig {
                key_id: "Not Stable".to_string(),
                private_jwk: private_jwk.clone(),
            },
            verification_keys: vec![],
        };
        let mismatched_key = BadgesConfig {
            signing_key: BadgeSigningKeyConfig {
                key_id: "active-2026".to_string(),
                private_jwk: mismatched,
            },
            verification_keys: vec![],
        };
        let duplicate = BadgesConfig {
            signing_key: BadgeSigningKeyConfig {
                key_id: "active-2026".to_string(),
                private_jwk,
            },
            verification_keys: vec![BadgeVerificationKeyConfig {
                key_id: "active-2026".to_string(),
                public_jwk,
            }],
        };
        // Validate each inconsistent key configuration
        let duplicate_result = duplicate.validate();
        let invalid_id_result = invalid_id.validate();
        let mismatched_key_result = mismatched_key.validate();

        // Check every inconsistent configuration is rejected
        assert!(duplicate_result.is_err());
        assert!(invalid_id_result.is_err());
        assert!(mismatched_key_result.is_err());
    }

    #[test]
    fn test_config_debug_redacts_sensitive_values() {
        // Setup config with sentinel secret values
        let cfg = sample_config();
        let outputs = [
            format!("{cfg:?}"),
            format!("{:?}", cfg.email.smtp),
            format!("{:?}", cfg.images),
            format!("{:?}", cfg.meetings),
            format!("{:?}", cfg.payments),
            format!("{:?}", cfg.server.badges),
            format!("{:?}", cfg.server.oauth2),
            format!("{:?}", cfg.server.oidc),
        ];

        // Check root and nested debug output redacts all secret values
        for output in outputs {
            for sensitive_value in sensitive_values() {
                assert!(
                    !output.contains(sensitive_value),
                    "debug output exposed sensitive value '{sensitive_value}': {output}"
                );
            }
            assert!(output.contains(REDACTED_CONFIG_VALUE));
        }
    }

    #[test]
    fn test_config_rejects_missing_badges_configuration() {
        // Remove the required badge configuration from an otherwise valid config
        let mut cfg = sample_config();
        cfg.server.badges = None;

        // Validate the complete startup configuration
        let result = cfg.validate();

        // Check startup rejects a partially configured public badge service
        assert_eq!(result.unwrap_err().to_string(), "server.badges is required");
    }

    // Helpers.

    fn sample_config() -> Config {
        let badge_signing_key = JWK::generate_ed25519().unwrap();
        let mut oauth2 = HashMap::new();
        oauth2.insert(
            OAuth2Provider::GitHub,
            OAuth2ProviderConfig {
                auth_url: "https://github.example.test/auth".to_string(),
                client_id: "github-client-id".to_string(),
                client_secret: "oauth2-sensitive-value".to_string(),
                redirect_uri: "https://app.example.test/auth/github/callback".to_string(),
                scopes: vec!["user:email".to_string()],
                token_url: "https://github.example.test/token".to_string(),
            },
        );

        let mut oidc = HashMap::new();
        oidc.insert(
            OidcProvider::LinuxFoundation,
            OidcProviderConfig {
                client_id: "lf-client-id".to_string(),
                client_secret: "oidc-sensitive-value".to_string(),
                issuer_url: "https://oidc.example.test".to_string(),
                redirect_uri: "https://app.example.test/auth/lf/callback".to_string(),
                scopes: vec!["openid".to_string(), "email".to_string()],
            },
        );

        Config {
            db: sample_db_config(),
            email: EmailConfig {
                from_address: "noreply@example.test".to_string(),
                from_name: "OCG".to_string(),
                smtp: SmtpConfig {
                    host: "smtp.example.test".to_string(),
                    password: "smtp-sensitive-value".to_string(),
                    port: 587,
                    username: "smtp-user".to_string(),
                },
                rcpts_whitelist: None,
            },
            images: ImageStorageConfig::S3(ImageStorageConfigS3 {
                access_key_id: "s3-access-key-id".to_string(),
                bucket: "images".to_string(),
                region: "eu-west-1".to_string(),
                secret_access_key: "s3-sensitive-value".to_string(),
                endpoint: Some("https://s3.example.test".to_string()),
                force_path_style: Some(true),
            }),
            log: LogConfig {
                format: LogFormat::Json,
            },
            server: HttpServerConfig {
                addr: "127.0.0.1:9000".to_string(),
                base_url: "https://app.example.test".to_string(),
                disable_referer_checks: false,
                login: LoginOptions {
                    email: true,
                    github: true,
                    linuxfoundation: true,
                },
                oauth2,
                oidc,
                badges: Some(BadgesConfig {
                    signing_key: BadgeSigningKeyConfig {
                        key_id: "config-test".to_string(),
                        private_jwk: badge_signing_key,
                    },
                    verification_keys: vec![],
                }),
                cookie: None,
                redirect_hosts: None,
            },
            meetings: Some(MeetingsConfig {
                zoom: Some(MeetingsZoomConfig {
                    account_id: "zoom-account-id".to_string(),
                    client_id: "zoom-client-id".to_string(),
                    client_secret: "zoom-client-sensitive-value".to_string(),
                    enabled: true,
                    host_pool_users: vec!["host@example.test".to_string()],
                    max_participants: 100,
                    max_simultaneous_meetings_per_host: 2,
                    webhook_secret_token: "zoom-webhook-sensitive-value".to_string(),
                }),
            }),
            payments: Some(PaymentsConfig::Stripe(PaymentsStripeConfig {
                mode: PaymentMode::Test,
                publishable_key: "pk_test_public".to_string(),
                secret_key: "stripe-key-sensitive-value".to_string(),
                webhook_secret: "stripe-webhook-sensitive-value".to_string(),
            })),
        }
    }

    fn sample_db_config() -> DbConfig {
        let url = "postgres://user:db-url-sensitive-value@db.example.test/ocg";
        let mut connection = DeadpoolDbConfig::new();
        connection.password = Some("db-password-sensitive-value".to_string());
        connection.url = Some(url.to_string());

        DbConfig {
            connection,

            tls: None,
        }
    }

    fn sensitive_values() -> [&'static str; 10] {
        [
            "db-password-sensitive-value",
            "db-url-sensitive-value",
            "oauth2-sensitive-value",
            "oidc-sensitive-value",
            "s3-sensitive-value",
            "smtp-sensitive-value",
            "stripe-key-sensitive-value",
            "stripe-webhook-sensitive-value",
            "zoom-client-sensitive-value",
            "zoom-webhook-sensitive-value",
        ]
    }
}
