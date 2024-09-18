//! This module defines some types to represent the configuration.

use anyhow::Result;
use deadpool_postgres::Config as DbConfig;
use figment::{
    providers::{Env, Format, Serialized, Yaml},
    Figment,
};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// Server configuration.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub(crate) struct Config {
    pub db: DbConfig,
    pub log: LogConfig,
    pub server: HttpServerConfig,
}

impl Config {
    /// Create a new Config instance.
    pub(crate) fn new(config_file: &Option<PathBuf>) -> Result<Self> {
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

/// Http server configuration.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub(crate) struct HttpServerConfig {
    pub addr: String,
}

/// Logs configuration.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub(crate) struct LogConfig {
    pub format: LogFormat,
}

/// Format to use in logs.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum LogFormat {
    Json,
    Pretty,
}
