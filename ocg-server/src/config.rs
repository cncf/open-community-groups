//! Configuration management for the OCG server.
//!
//! This module handles loading and parsing configuration from multiple sources using
//! Figment. Configuration can be provided via:
//!
//! - YAML configuration file
//! - Environment variables (with OCG_ prefix)

use std::path::PathBuf;

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

/// HTTP server configuration settings.
///
/// Defines the server's listening address and optional basic authentication
/// credentials.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub(crate) struct HttpServerConfig {
    /// The address the HTTP server will listen on.
    pub addr: String,
    /// Optional basic authentication configuration.
    pub basic_auth: Option<BasicAuth>,
}

/// Basic authentication configuration for the HTTP server.
///
/// When enabled, all requests must provide valid credentials via HTTP Basic
/// Authentication.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub(crate) struct BasicAuth {
    /// Whether basic authentication is enabled.
    pub enabled: bool,
    /// Username for basic authentication.
    pub username: String,
    /// Password for basic authentication.
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
