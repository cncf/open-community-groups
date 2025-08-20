//! Configuration management for the OCG server.
//!
//! This module handles loading and parsing configuration from multiple sources using
//! Figment. Configuration can be provided via:
//!
//! - YAML configuration file
//! - Environment variables (with OCG_ prefix)

use std::{collections::HashMap, path::PathBuf};

use anyhow::Result;
use deadpool_postgres::Config as DbConfig;
use figment::{
    Figment,
    providers::{Env, Format, Serialized, Yaml},
};
use serde::{Deserialize, Serialize};
use tracing::instrument;

/// Root configuration structure for the OCG server.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub(crate) struct Config {
    /// Database configuration.
    pub db: DbConfig,
    /// Email configuration.
    pub email: EmailConfig,
    /// Logging configuration.
    pub log: LogConfig,
    /// HTTP server configuration.
    pub server: HttpServerConfig,
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
            .merge(Serialized::default("server.addr", "127.0.0.1:9000"));

        if let Some(config_file) = config_file {
            figment = figment.merge(Yaml::file(config_file));
        }

        figment
            .merge(Env::prefixed("OCG_").split("__"))
            .extract()
            .map_err(Into::into)
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
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
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

    /// Optional cookie configuration.
    pub cookie: Option<CookieConfig>,
}

/// Cookie settings configuration.
#[derive(Debug, Clone, Default, PartialEq, Deserialize, Serialize)]
pub(crate) struct CookieConfig {
    /// Whether cookies should be secure (HTTPS only).
    pub secure: Option<bool>,
}

/// Login options enabled for the server.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
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
