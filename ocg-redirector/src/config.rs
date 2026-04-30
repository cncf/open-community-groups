//! Configuration management for the OCG redirector.

use std::{path::PathBuf, str::FromStr};

use anyhow::{Result, anyhow};
use axum::http::Uri;
use deadpool_postgres::Config as DbConfig;
use figment::{
    Figment,
    providers::{Env, Format, Serialized, Yaml},
};
use serde::{Deserialize, Serialize};
use tracing::instrument;

/// Root configuration structure for the OCG redirector.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub(crate) struct Config {
    /// Database configuration.
    pub db: DbConfig,
    /// Logging configuration.
    pub log: LogConfig,
    /// HTTP server configuration.
    pub server: HttpServerConfig,
}

impl Config {
    /// Creates a new Config instance from available configuration sources.
    #[instrument(err)]
    pub(crate) fn new(config_file: Option<&PathBuf>) -> Result<Self> {
        let mut figment = Figment::new()
            .merge(Serialized::default("log.format", "json"))
            .merge(Serialized::default("server.addr", "127.0.0.1:9001"));

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

    /// Validates configuration consistency after loading from all sources.
    fn validate(&self) -> Result<()> {
        validate_url(&self.server.base_redirect_url, "server.base_redirect_url")?;

        Ok(())
    }
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
    /// Base URL used for matched redirects.
    pub base_redirect_url: String,
}

impl HttpServerConfig {
    /// Returns the redirect host suffix derived from the base redirect URL.
    pub(crate) fn redirect_host_suffix(&self) -> String {
        let uri = Uri::from_str(&self.base_redirect_url)
            .expect("server.base_redirect_url must be validated before router setup");
        let host = uri.host().expect("server.base_redirect_url must include a host");

        format!("redirects.{host}")
    }
}

/// Validates that the provided string is an absolute HTTP(S) URL.
fn validate_url(value: &str, field_name: &str) -> Result<()> {
    let uri = Uri::from_str(value).map_err(|err| anyhow!("{field_name} is invalid: {err}"))?;
    let has_http_scheme = matches!(uri.scheme_str(), Some("http" | "https"));

    if !has_http_scheme || uri.host().is_none() {
        return Err(anyhow!("{field_name} must be an absolute http(s) URL"));
    }

    Ok(())
}
