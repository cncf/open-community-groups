//! Configuration management for the OCG redirector.

use std::{fmt, path::PathBuf, str::FromStr};

use anyhow::{Result, anyhow};
use axum::http::Uri;
use figment::{
    Figment,
    providers::{Env, Format, Serialized, Yaml},
};
use ocg_common::config::{DbConfig, LogConfig};
use serde::{Deserialize, Serialize};
use tracing::instrument;

/// Placeholder used when formatting sensitive configuration values.
const REDACTED_CONFIG_VALUE: &str = "[redacted]";

/// Root configuration structure for the OCG redirector.
#[derive(Clone, Deserialize, Serialize)]
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
        // Validate database transport security before starting the service
        self.db.validate()?;

        // Validate the redirect target configuration
        validate_url(&self.server.base_redirect_url, "server.base_redirect_url")?;

        Ok(())
    }
}

impl fmt::Debug for Config {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Config")
            .field("db", &REDACTED_CONFIG_VALUE)
            .field("log", &self.log)
            .field("server", &self.server)
            .finish()
    }
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

#[cfg(test)]
mod tests {
    use deadpool_postgres::Config as DeadpoolDbConfig;
    use ocg_common::config::LogFormat;

    use super::*;

    #[test]
    fn test_config_debug_redacts_database_credentials() {
        // Setup a configuration containing sentinel database credentials
        let cfg = sample_config();

        // Format the complete startup configuration
        let output = format!("{cfg:?}");

        // Check database credentials cannot enter logs or errors through Debug
        assert!(output.contains(REDACTED_CONFIG_VALUE));
        assert!(!output.contains("database-password-sensitive-value"));
    }

    #[test]
    fn test_config_validate_checks_base_redirect_url() {
        // (case, base_redirect_url, expected error)
        let cases = [
            ("https URL", "https://ocg.example.test", None),
            ("http URL with port", "http://localhost:9000", None),
            (
                "relative URL",
                "/community",
                Some("server.base_redirect_url must be an absolute http(s) URL"),
            ),
            (
                "unsupported scheme",
                "ftp://ocg.example.test",
                Some("server.base_redirect_url must be an absolute http(s) URL"),
            ),
            (
                "unparseable URL",
                "https://ocg example",
                Some("server.base_redirect_url is invalid: invalid uri character"),
            ),
        ];

        for (case, base_redirect_url, expected) in cases {
            let mut cfg = sample_config();
            cfg.server.base_redirect_url = base_redirect_url.to_string();

            let result = cfg.validate().map_err(|err| err.to_string());

            assert_eq!(result.err().as_deref(), expected, "{case}");
        }
    }

    #[test]
    fn test_http_server_config_redirect_host_suffix_uses_base_url_host() {
        for (case, base_redirect_url) in [
            ("bare host", "https://ocg.example.test"),
            ("trailing slash", "https://ocg.example.test/"),
            ("port and path", "http://ocg.example.test:9000/base"),
        ] {
            let server_cfg = HttpServerConfig {
                base_redirect_url: base_redirect_url.to_string(),
                ..HttpServerConfig::default()
            };

            assert_eq!(
                server_cfg.redirect_host_suffix(),
                "redirects.ocg.example.test",
                "{case}"
            );
        }
    }

    // Helpers.

    fn sample_config() -> Config {
        Config {
            db: sample_db_config(),
            log: LogConfig {
                format: LogFormat::Json,
            },
            server: HttpServerConfig {
                addr: "127.0.0.1:9001".to_string(),
                base_redirect_url: "https://ocg.example.test".to_string(),
            },
        }
    }

    fn sample_db_config() -> DbConfig {
        let mut connection = DeadpoolDbConfig::new();
        connection.dbname = Some("ocg".to_string());
        connection.password = Some("database-password-sensitive-value".to_string());

        DbConfig {
            connection,

            tls: None,
        }
    }
}
