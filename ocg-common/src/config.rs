//! Configuration types shared by the OCG binaries.

use anyhow::{Context, Result, bail};
use deadpool_postgres::Config as DeadpoolDbConfig;
use serde::{Deserialize, Serialize};
use tokio_postgres::config::SslMode;

/// Database connection and TLS configuration.
#[derive(Clone, Deserialize, Serialize)]
pub struct DbConfig {
    /// Postgres connection and pool configuration.
    #[serde(flatten)]
    pub connection: DeadpoolDbConfig,

    /// TLS certificate verification configuration.
    pub tls: Option<DbTlsConfig>,
}

impl DbConfig {
    /// Validates database TLS configuration consistency.
    ///
    /// # Errors
    ///
    /// Returns an error when the TLS mode, CA certificate, and SSL mode
    /// combination is inconsistent.
    pub fn validate(&self) -> Result<()> {
        let Some(tls) = &self.tls else {
            return Ok(());
        };

        // Reject CA material that certificate verification would ignore
        if tls.mode == DbTlsMode::None && tls.ca_cert.is_some() {
            bail!("db.tls.ca_cert requires db.tls.mode verify-ca or verify-full");
        }

        // Require explicit trust roots for certificate verification
        if tls.mode != DbTlsMode::None && tls.ca_cert.is_none() {
            bail!("db.tls.ca_cert is required when db.tls.mode enables certificate verification");
        }

        // Prevent certificate verification from allowing plaintext fallback
        if tls.mode != DbTlsMode::None {
            let ssl_mode = self
                .connection
                .get_pg_config()
                .context("invalid database connection configuration")?
                .get_ssl_mode();
            if ssl_mode != SslMode::Require {
                bail!(
                    "db.ssl_mode must be Require when db.tls.mode enables certificate verification"
                );
            }
        }

        Ok(())
    }
}

/// Postgres TLS certificate verification configuration.
#[derive(Clone, Deserialize, Serialize)]
pub struct DbTlsConfig {
    /// Certificate verification mode.
    pub mode: DbTlsMode,

    /// Optional trusted CA certificate bundle in PEM format.
    pub ca_cert: Option<String>,
}

/// Supported Postgres TLS certificate verification modes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum DbTlsMode {
    /// Disables certificate verification.
    None,
    /// Verifies the certificate chain without checking the hostname.
    VerifyCa,
    /// Verifies the certificate chain and hostname.
    VerifyFull,
}

/// Logging configuration.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub struct LogConfig {
    /// Log output format.
    pub format: LogFormat,
}

/// Supported log output formats.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum LogFormat {
    /// JSON log format.
    Json,
    /// Human-readable log format.
    Pretty,
}

#[cfg(test)]
mod tests {
    use deadpool_postgres::SslMode as DeadpoolSslMode;
    use figment::{
        Figment,
        providers::{Format, Yaml},
    };

    use super::*;

    #[test]
    fn test_database_config_deserializes_tls_fields() {
        // Setup the chart-compatible flattened database configuration
        let yaml = r"
host: db.example.test
ssl_mode: Require
tls:
  mode: verify-full
  ca_cert: trusted CA certificate
";

        // Deserialize the database configuration through Figment
        let db: DbConfig = Figment::new().merge(Yaml::string(yaml)).extract().unwrap();

        // Check connection and TLS fields retain the public YAML shape
        assert_eq!(db.connection.host.as_deref(), Some("db.example.test"));
        assert_eq!(db.connection.ssl_mode, Some(DeadpoolSslMode::Require));
        let tls = db.tls.expect("TLS configuration should be present");
        assert_eq!(tls.mode, DbTlsMode::VerifyFull);
        assert_eq!(tls.ca_cert.as_deref(), Some("trusted CA certificate"));
    }

    #[test]
    fn test_database_config_validate_checks_tls_policy() {
        let require = Some(DeadpoolSslMode::Require);
        let ca_cert = Some("trusted CA certificate");
        let verification_without_tls =
            "db.ssl_mode must be Require when db.tls.mode enables certificate verification";
        // (case, ssl_mode, tls mode and CA certificate, expected error)
        let cases = [
            ("default configuration", None, None, None),
            (
                "full verification over required TLS",
                require,
                Some((DbTlsMode::VerifyFull, ca_cert)),
                None,
            ),
            (
                "CA certificate without verification",
                None,
                Some((DbTlsMode::None, Some("unused CA certificate"))),
                Some("db.tls.ca_cert requires db.tls.mode verify-ca or verify-full"),
            ),
            (
                "verification without CA certificate",
                require,
                Some((DbTlsMode::VerifyFull, None)),
                Some(
                    "db.tls.ca_cert is required when db.tls.mode enables certificate verification",
                ),
            ),
            (
                "verification without ssl mode",
                None,
                Some((DbTlsMode::VerifyCa, ca_cert)),
                Some(verification_without_tls),
            ),
            (
                "verification with disabled ssl",
                Some(DeadpoolSslMode::Disable),
                Some((DbTlsMode::VerifyCa, ca_cert)),
                Some(verification_without_tls),
            ),
            (
                "verification with preferred ssl",
                Some(DeadpoolSslMode::Prefer),
                Some((DbTlsMode::VerifyCa, ca_cert)),
                Some(verification_without_tls),
            ),
        ];

        for (case, ssl_mode, tls, expected) in cases {
            let mut db = sample_db_config();
            db.connection.ssl_mode = ssl_mode;
            db.tls = tls.map(|(mode, ca_cert)| DbTlsConfig {
                mode,

                ca_cert: ca_cert.map(str::to_string),
            });

            let result = db.validate().map_err(|err| err.to_string());

            assert_eq!(result.err().as_deref(), expected, "{case}");
        }
    }

    // Helpers.

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
