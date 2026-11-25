//! Database helpers shared by the OCG binaries.

use std::time::Duration;

use anyhow::{Context, Result, bail};
use deadpool_postgres::{
    Config as DeadpoolDbConfig, Hook, Manager, ManagerConfig, Pool, PoolConfig, RecyclingMethod,
    Runtime,
};
use openssl::{
    ssl::{SslConnector, SslMethod, SslVerifyMode},
    x509::X509,
};
use postgres_openssl::MakeTlsConnector;
use tokio_postgres::{
    Config as PgConfig, Socket,
    tls::{MakeTlsConnect, TlsConnect},
};

use crate::config::{DbTlsConfig, DbTlsMode};

/// Default timeout for establishing a new database connection.
const DB_POOL_CREATE_TIMEOUT: Duration = Duration::from_secs(10);

/// Default timeout for recycling a database connection.
const DB_POOL_RECYCLE_TIMEOUT: Duration = Duration::from_secs(5);

/// Default timeout when waiting for an available database connection.
const DB_POOL_WAIT_TIMEOUT: Duration = Duration::from_secs(5);

/// Default `idle_in_transaction_session_timeout` startup option.
const DB_SESSION_IDLE_IN_TX_OPTION: (&str, &str) = (
    "idle_in_transaction_session_timeout",
    "-c idle_in_transaction_session_timeout=60000",
);

/// Default session options sent on connection startup.
///
/// `statement_timeout` bounds every statement, including lock waits, and
/// `idle_in_transaction_session_timeout` closes sessions whose transaction was
/// left open. Both are cancelled server-side, so the statement or transaction
/// is rolled back before the client observes the error. Startup options are the
/// session defaults, so they survive the session reset run when connections are
/// recycled.
const DB_SESSION_OPTIONS: &str =
    "-c statement_timeout=30000 -c idle_in_transaction_session_timeout=60000";

/// Default `statement_timeout` startup option.
const DB_SESSION_STATEMENT_TIMEOUT_OPTION: (&str, &str) =
    ("statement_timeout", "-c statement_timeout=30000");

/// Default idle time before the first TCP keepalive probe is sent.
const DB_TCP_KEEPALIVES_IDLE: Duration = Duration::from_secs(30);

/// Default interval between TCP keepalive probes.
const DB_TCP_KEEPALIVES_INTERVAL: Duration = Duration::from_secs(10);

/// Default number of unanswered TCP keepalive probes before the connection is closed.
const DB_TCP_KEEPALIVES_RETRIES: u32 = 3;

/// Default time transmitted data may stay unacknowledged before the connection
/// is closed.
///
/// Together with the keepalive defaults it bounds how long a caller waits on a
/// connection whose network path died without closing it. Acknowledged
/// statements are unaffected, however long the server takes to answer them.
const DB_TCP_USER_TIMEOUT: Duration = Duration::from_secs(10);

/// Creates a Postgres connection pool, applying hardened defaults when unset.
///
/// `default_max_size` sets the pool capacity only when the deployment
/// configuration omits `pool`.
///
/// # Errors
///
/// Returns an error when the Postgres connection settings are invalid or the
/// pool cannot be built.
pub fn create_pool<T>(cfg: &DeadpoolDbConfig, tls: T, default_max_size: usize) -> Result<Pool>
where
    T: MakeTlsConnect<Socket> + Clone + Send + Sync + 'static,
    T::Stream: Send + Sync,
    T::TlsConnect: Send + Sync,
    <T::TlsConnect as TlsConnect<Socket>>::Future: Send,
{
    // Apply the defaults the deployment config leaves unset
    let cfg = config_with_defaults(cfg, default_max_size);
    let pg_cfg = pg_config_with_defaults(&cfg)?;

    // Build the pool from the resulting configuration
    let manager_cfg = cfg.get_manager_config();
    let clears_statement_cache = recycle_may_deallocate_statements(&manager_cfg.recycling_method);
    let manager = Manager::from_config(pg_cfg, tls, manager_cfg);
    let mut builder = Pool::builder(manager)
        .config(cfg.get_pool_config())
        .runtime(Runtime::Tokio1);

    // Drop cached statements a custom recycle query may have deallocated
    if clears_statement_cache {
        builder = builder.post_recycle(Hook::sync_fn(|client, _| {
            client.statement_cache.clear();
            Ok(())
        }));
    }

    Ok(builder.build()?)
}

/// Builds the Postgres TLS connector from the configured verification policy.
///
/// # Errors
///
/// Returns an error when certificate verification is enabled without trust
/// roots or when the CA certificate bundle cannot be loaded.
pub fn tls_connector(tls: Option<&DbTlsConfig>) -> Result<MakeTlsConnector> {
    // Require explicit trust roots for certificate verification
    let mode = tls.map_or(DbTlsMode::None, |tls| tls.mode);
    let ca_cert = tls.and_then(|tls| tls.ca_cert.as_deref());
    if mode != DbTlsMode::None && ca_cert.is_none() {
        bail!("db.tls.ca_cert is required when db.tls.mode enables certificate verification");
    }

    // Configure certificate-chain verification for the selected TLS mode
    let mut builder =
        SslConnector::builder(SslMethod::tls()).context("error creating database TLS connector")?;
    builder.set_verify(match mode {
        DbTlsMode::None => SslVerifyMode::NONE,
        DbTlsMode::VerifyCa | DbTlsMode::VerifyFull => SslVerifyMode::PEER,
    });

    // Load every certificate in the configured PEM bundle into the trust store
    if let Some(ca_cert) = ca_cert {
        let certificates =
            X509::stack_from_pem(ca_cert.as_bytes()).context("db.tls.ca_cert is not valid PEM")?;
        if certificates.is_empty() {
            bail!("db.tls.ca_cert does not contain a certificate");
        }

        for certificate in certificates {
            builder
                .cert_store_mut()
                .add_cert(certificate)
                .context("error adding db.tls.ca_cert to the database trust store")?;
        }
    }

    // Disable only hostname verification for verify-ca connections
    let mut connector = MakeTlsConnector::new(builder.build());
    if mode == DbTlsMode::VerifyCa {
        connector.set_callback(|configuration, _| {
            configuration.set_verify_hostname(false);
            Ok(())
        });
    }

    Ok(connector)
}

/// Applies hardened defaults to the database pool configuration.
fn config_with_defaults(cfg: &DeadpoolDbConfig, default_max_size: usize) -> DeadpoolDbConfig {
    let mut cfg = cfg.clone();

    // Reset session state when recycling connections
    cfg.manager.get_or_insert(ManagerConfig {
        recycling_method: RecyclingMethod::Clean,
    });

    // Bound pool capacity and waits when deployment config does not override them
    let pool_cfg = cfg.pool.get_or_insert_with(|| PoolConfig::new(default_max_size));
    pool_cfg.timeouts.create.get_or_insert(DB_POOL_CREATE_TIMEOUT);
    pool_cfg.timeouts.recycle.get_or_insert(DB_POOL_RECYCLE_TIMEOUT);
    pool_cfg.timeouts.wait.get_or_insert(DB_POOL_WAIT_TIMEOUT);

    cfg
}

/// Returns whether `cfg` explicitly sets `keepalives_idle` via field or URL.
fn has_explicit_keepalives_idle(cfg: &DeadpoolDbConfig) -> bool {
    cfg.keepalives_idle.is_some()
        || cfg
            .url
            .as_deref()
            .is_some_and(|url| url_sets_param(url, "keepalives_idle"))
}

/// Returns whether a PostgreSQL `options` string already sets `key`.
fn options_sets_key(options: &str, key: &str) -> bool {
    let mut expect_c_arg = false;

    // Scan tokens matching `-c <key>=...`, `-c<key>=...`, and `--<key>=...`
    for token in options.split_whitespace() {
        if expect_c_arg {
            expect_c_arg = false;
            if token.strip_prefix(key).is_some_and(|rest| rest.starts_with('=')) {
                return true;
            }
            continue;
        }

        if token == "-c" {
            expect_c_arg = true;
            continue;
        }

        if let Some(arg) = token.strip_prefix("-c").or_else(|| token.strip_prefix("--"))
            && arg.strip_prefix(key).is_some_and(|rest| rest.starts_with('='))
        {
            return true;
        }
    }

    false
}

/// Builds the connection configuration, applying hardened defaults to its
/// session and socket bounds.
///
/// The pool configuration only carries some of the connection options as
/// fields; others (including `options`) can also come from its connection
/// string. The defaults are therefore applied to the resolved connection
/// configuration so URL-supplied values are preserved.
fn pg_config_with_defaults(cfg: &DeadpoolDbConfig) -> Result<PgConfig> {
    let mut pg_cfg = cfg
        .get_pg_config()
        .context("invalid database connection configuration")?;

    // Bound statement and idle-transaction time without discarding custom startup options
    let options = session_options_with_defaults(pg_cfg.get_options());
    pg_cfg.options(&options);

    // Probe idle connections early when deployment config does not set keepalives_idle
    if !has_explicit_keepalives_idle(cfg) {
        pg_cfg.keepalives_idle(DB_TCP_KEEPALIVES_IDLE);
    }
    if pg_cfg.get_keepalives_interval().is_none() {
        pg_cfg.keepalives_interval(DB_TCP_KEEPALIVES_INTERVAL);
    }
    if pg_cfg.get_keepalives_retries().is_none() {
        pg_cfg.keepalives_retries(DB_TCP_KEEPALIVES_RETRIES);
    }

    // Bound unacknowledged data when deployment config does not override it
    if pg_cfg.get_tcp_user_timeout().is_none() {
        pg_cfg.tcp_user_timeout(DB_TCP_USER_TIMEOUT);
    }

    Ok(pg_cfg)
}

/// Returns whether recycling with this method may deallocate prepared statements.
///
/// The built-in methods never deallocate them. A custom recycle query is
/// arbitrary SQL, such as `DISCARD ALL`, so the connection's statement cache is
/// cleared after every custom recycle instead of parsing the query.
fn recycle_may_deallocate_statements(method: &RecyclingMethod) -> bool {
    matches!(method, RecyclingMethod::Custom(_))
}

/// Prepends missing default session timeout flags to any configured `options`.
fn session_options_with_defaults(configured: Option<&str>) -> String {
    let Some(configured) = configured.map(str::trim).filter(|value| !value.is_empty()) else {
        return DB_SESSION_OPTIONS.to_string();
    };

    // Collect only the default timeout flags not already set by deployment config
    let mut parts = Vec::with_capacity(3);
    for (key, flag) in [
        DB_SESSION_STATEMENT_TIMEOUT_OPTION,
        DB_SESSION_IDLE_IN_TX_OPTION,
    ] {
        if !options_sets_key(configured, key) {
            parts.push(flag);
        }
    }
    parts.push(configured);

    parts.join(" ")
}

/// Returns whether a PostgreSQL URI or key-value connection string sets `param`.
fn url_sets_param(url: &str, param: &str) -> bool {
    // Check URI query parameters when using postgres:// or postgresql:// form
    if url.starts_with("postgres://") || url.starts_with("postgresql://") {
        let Some((_, query)) = url.split_once('?') else {
            return false;
        };
        let query = query.split('#').next().unwrap_or(query);
        return query
            .split('&')
            .any(|pair| pair.split_once('=').is_some_and(|(key, _)| key == param));
    }

    // Parse libpq key=value pairs while skipping quoted values
    let bytes = url.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        while i < bytes.len() && bytes[i].is_ascii_whitespace() {
            i += 1;
        }
        let key_start = i;
        while i < bytes.len() && bytes[i] != b'=' && !bytes[i].is_ascii_whitespace() {
            i += 1;
        }
        let key = &url[key_start..i];
        while i < bytes.len() && bytes[i].is_ascii_whitespace() {
            i += 1;
        }
        if i >= bytes.len() || bytes[i] != b'=' {
            return false;
        }
        i += 1;
        if key == param {
            return true;
        }

        // Advance past the value (single-quoted or unquoted)
        while i < bytes.len() && bytes[i].is_ascii_whitespace() {
            i += 1;
        }
        if i < bytes.len() && bytes[i] == b'\'' {
            i += 1;
            while i < bytes.len() {
                if bytes[i] == b'\\' && i + 1 < bytes.len() {
                    i += 2;
                } else if bytes[i] == b'\'' {
                    i += 1;
                    break;
                } else {
                    i += 1;
                }
            }
        } else {
            while i < bytes.len() && !bytes[i].is_ascii_whitespace() {
                i += 1;
            }
        }
    }

    false
}

#[cfg(test)]
mod tests {
    use std::{
        net::{SocketAddr, TcpListener},
        thread::{self, JoinHandle},
    };

    use openssl::{
        asn1::Asn1Time,
        bn::BigNum,
        hash::MessageDigest,
        pkey::{PKey, Private},
        rsa::Rsa,
        ssl::SslAcceptor,
        x509::{
            X509, X509NameBuilder,
            extension::{BasicConstraints, KeyUsage, SubjectAlternativeName},
        },
    };
    use tokio::net::TcpStream;
    use tokio_postgres::tls::{MakeTlsConnect, TlsConnect};

    use super::*;

    #[test]
    fn test_config_with_defaults_applies_missing_defaults() {
        for default_max_size in [4, 25] {
            let cfg = config_with_defaults(&DeadpoolDbConfig::new(), default_max_size);

            let manager = cfg.manager.expect("manager config should be set");
            assert_eq!(manager.recycling_method, RecyclingMethod::Clean);

            let pool = cfg.pool.expect("pool config should be set");
            assert_eq!(pool.max_size, default_max_size);
            assert_eq!(pool.timeouts.create, Some(DB_POOL_CREATE_TIMEOUT));
            assert_eq!(pool.timeouts.recycle, Some(DB_POOL_RECYCLE_TIMEOUT));
            assert_eq!(pool.timeouts.wait, Some(DB_POOL_WAIT_TIMEOUT));
        }
    }

    #[test]
    fn test_config_with_defaults_preserves_configured_values() {
        let mut cfg = DeadpoolDbConfig::new();
        cfg.manager = Some(ManagerConfig {
            recycling_method: RecyclingMethod::Fast,
        });
        cfg.pool = Some(PoolConfig::new(32));

        let pool = cfg.pool.as_mut().expect("pool config should be set");
        pool.timeouts.create = Some(Duration::from_secs(12));
        pool.timeouts.recycle = Some(Duration::from_secs(11));
        pool.timeouts.wait = Some(Duration::from_secs(10));

        let cfg = config_with_defaults(&cfg, 25);

        let manager = cfg.manager.expect("manager config should be set");
        assert_eq!(manager.recycling_method, RecyclingMethod::Fast);

        let pool = cfg.pool.expect("pool config should be set");
        assert_eq!(pool.max_size, 32);
        assert_eq!(pool.timeouts.create, Some(Duration::from_secs(12)));
        assert_eq!(pool.timeouts.recycle, Some(Duration::from_secs(11)));
        assert_eq!(pool.timeouts.wait, Some(Duration::from_secs(10)));
    }

    #[test]
    fn test_pg_config_with_defaults_applies_missing_defaults() {
        let mut cfg = DeadpoolDbConfig::new();
        cfg.dbname = Some("ocg".to_string());

        let pg_cfg = pg_config_with_defaults(&cfg).expect("connection config should be valid");

        assert_eq!(pg_cfg.get_options(), Some(DB_SESSION_OPTIONS));
        assert_eq!(pg_cfg.get_keepalives_idle(), DB_TCP_KEEPALIVES_IDLE);
        assert_eq!(
            pg_cfg.get_keepalives_interval(),
            Some(DB_TCP_KEEPALIVES_INTERVAL)
        );
        assert_eq!(
            pg_cfg.get_keepalives_retries(),
            Some(DB_TCP_KEEPALIVES_RETRIES)
        );
        assert_eq!(pg_cfg.get_tcp_user_timeout(), Some(&DB_TCP_USER_TIMEOUT));
    }

    #[test]
    fn test_pg_config_with_defaults_preserves_configured_values() {
        let mut cfg = DeadpoolDbConfig::new();
        cfg.dbname = Some("ocg".to_string());
        cfg.options = Some("-c statement_timeout=5000".to_string());
        cfg.keepalives_idle = Some(Duration::from_secs(45));
        cfg.url = Some("keepalives_interval=7 keepalives_retries=9 tcp_user_timeout=5".to_string());

        let pg_cfg = pg_config_with_defaults(&cfg).expect("connection config should be valid");

        assert_eq!(
            pg_cfg.get_options(),
            Some("-c idle_in_transaction_session_timeout=60000 -c statement_timeout=5000")
        );
        assert_eq!(pg_cfg.get_keepalives_idle(), Duration::from_secs(45));
        assert_eq!(
            pg_cfg.get_keepalives_interval(),
            Some(Duration::from_secs(7))
        );
        assert_eq!(pg_cfg.get_keepalives_retries(), Some(9));
        assert_eq!(pg_cfg.get_tcp_user_timeout(), Some(&Duration::from_secs(5)));
    }

    #[test]
    fn test_pg_config_with_defaults_preserves_explicit_driver_default_keepalives_idle() {
        // Check explicit 7200s (matching tokio-postgres's built-in default) is preserved
        // whether set via field, URI query, or key-value connection string
        let driver_default = PgConfig::new().get_keepalives_idle();
        let secs = driver_default.as_secs();

        let mut from_field = DeadpoolDbConfig::new();
        from_field.dbname = Some("ocg".to_string());
        from_field.keepalives_idle = Some(driver_default);
        assert_eq!(
            pg_config_with_defaults(&from_field)
                .expect("field config should be valid")
                .get_keepalives_idle(),
            driver_default
        );

        let mut from_uri = DeadpoolDbConfig::new();
        from_uri.url = Some(format!("postgres://localhost/ocg?keepalives_idle={secs}"));
        assert_eq!(
            pg_config_with_defaults(&from_uri)
                .expect("uri config should be valid")
                .get_keepalives_idle(),
            driver_default
        );

        let mut from_kv = DeadpoolDbConfig::new();
        from_kv.url = Some(format!("dbname=ocg keepalives_idle={secs}"));
        assert_eq!(
            pg_config_with_defaults(&from_kv)
                .expect("kv config should be valid")
                .get_keepalives_idle(),
            driver_default
        );

        let mut quoted_value = DeadpoolDbConfig::new();
        quoted_value.url = Some(format!("dbname=ocg password='keepalives_idle={secs}'"));
        assert_eq!(
            pg_config_with_defaults(&quoted_value)
                .expect("quoted value config should be valid")
                .get_keepalives_idle(),
            DB_TCP_KEEPALIVES_IDLE
        );
    }

    #[test]
    fn test_pg_config_with_defaults_preserves_options_from_url() {
        // Check an unrelated URL option keeps both default session timeouts
        let mut cfg = DeadpoolDbConfig::new();
        cfg.url = Some("postgres://localhost/ocg?options=-c%20search_path%3Dcustom".to_string());
        let cfg = config_with_defaults(&cfg, 4);
        let pg_cfg = pg_config_with_defaults(&cfg).expect("connection config should be valid");
        assert_eq!(
            pg_cfg.get_options(),
            Some(
                "-c statement_timeout=30000 -c idle_in_transaction_session_timeout=60000 -c search_path=custom"
            )
        );

        // Check explicit overrides for both timeout keys are preserved verbatim
        let mut both_overridden = DeadpoolDbConfig::new();
        both_overridden.dbname = Some("ocg".to_string());
        both_overridden.options =
            Some("--statement_timeout=0 -cidle_in_transaction_session_timeout=15000".to_string());
        let pg_cfg = pg_config_with_defaults(&both_overridden).expect("config should be valid");
        assert_eq!(
            pg_cfg.get_options(),
            Some("--statement_timeout=0 -cidle_in_transaction_session_timeout=15000")
        );
    }

    #[test]
    fn test_recycle_may_deallocate_statements_only_for_custom_queries() {
        let cases = [
            (RecyclingMethod::Clean, false),
            (RecyclingMethod::Custom("DISCARD ALL".to_string()), true),
            (RecyclingMethod::Custom("select 1".to_string()), true),
            (RecyclingMethod::Fast, false),
            (RecyclingMethod::Verified, false),
        ];

        for (method, expected) in cases {
            assert_eq!(
                recycle_may_deallocate_statements(&method),
                expected,
                "{method:?}"
            );
        }
    }

    #[tokio::test]
    async fn test_tls_connector_handshake_follows_verification_mode() {
        // Setup a trusted CA and server certificates chaining to it or to an unknown CA
        let trusted_ca = test_certificate_authority();
        let trusted_server = test_server_certificate(&trusted_ca);
        let untrusted_server = test_server_certificate(&test_certificate_authority());

        // (case, mode, server chains to the trusted CA, hostname, handshake succeeds)
        let cases = [
            (
                "disabled verification, untrusted chain",
                None,
                false,
                "localhost",
                true,
            ),
            (
                "verify-ca, hostname mismatch",
                Some(DbTlsMode::VerifyCa),
                true,
                "db.example.test",
                true,
            ),
            (
                "verify-ca, untrusted chain",
                Some(DbTlsMode::VerifyCa),
                false,
                "localhost",
                false,
            ),
            (
                "verify-full, trusted chain and hostname",
                Some(DbTlsMode::VerifyFull),
                true,
                "localhost",
                true,
            ),
            (
                "verify-full, hostname mismatch",
                Some(DbTlsMode::VerifyFull),
                true,
                "db.example.test",
                false,
            ),
            (
                "verify-full, untrusted chain",
                Some(DbTlsMode::VerifyFull),
                false,
                "localhost",
                false,
            ),
        ];

        for (case, mode, trusted_chain, hostname, succeeds) in cases {
            // Setup the server and the connector for the verification mode
            let server_certificate = if trusted_chain {
                &trusted_server
            } else {
                &untrusted_server
            };
            let (address, server) = spawn_tls_server(server_certificate);
            let tls = mode.map(|mode| DbTlsConfig {
                mode,

                ca_cert: Some(certificate_pem(&trusted_ca)),
            });
            let connector = tls_connector(tls.as_ref()).unwrap();

            // Perform the TLS handshake against the test server
            let result = tls_handshake(connector, address, hostname).await;

            // Check the handshake outcome matches the verification policy
            assert_eq!(result.is_ok(), succeeds, "{case}: {result:?}");
            server.join().unwrap();
        }
    }

    #[test]
    fn test_tls_connector_rejects_invalid_trust_configuration() {
        let invalid_pem = "-----BEGIN CERTIFICATE-----\nnot base64!\n-----END CERTIFICATE-----\n";
        // (case, mode, ca_cert, expected error)
        let cases = [
            (
                "empty bundle",
                DbTlsMode::VerifyCa,
                Some(""),
                "db.tls.ca_cert does not contain a certificate",
            ),
            (
                "text without PEM markers",
                DbTlsMode::VerifyCa,
                Some("not a certificate"),
                "db.tls.ca_cert does not contain a certificate",
            ),
            (
                "malformed certificate",
                DbTlsMode::VerifyCa,
                Some(invalid_pem),
                "db.tls.ca_cert is not valid PEM",
            ),
            (
                "verification without trust roots",
                DbTlsMode::VerifyFull,
                None,
                "db.tls.ca_cert is required when db.tls.mode enables certificate verification",
            ),
        ];

        for (case, mode, ca_cert, expected) in cases {
            let tls = DbTlsConfig {
                mode,

                ca_cert: ca_cert.map(str::to_string),
            };

            let error = tls_connector(Some(&tls)).err().expect(case);

            assert_eq!(error.to_string(), expected, "{case}");
        }
    }

    // Helpers.

    /// Test certificate paired with its private key.
    struct TestCertificate {
        certificate: X509,
        key: PKey<Private>,
    }

    /// Returns the PEM encoding of the given test certificate.
    fn certificate_pem(certificate: &TestCertificate) -> String {
        String::from_utf8(certificate.certificate.to_pem().unwrap()).unwrap()
    }

    /// Spawns a TLS server that accepts a single handshake attempt.
    fn spawn_tls_server(server: &TestCertificate) -> (SocketAddr, JoinHandle<()>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let (certificate, key) = (server.certificate.clone(), server.key.clone());

        let handle = thread::spawn(move || {
            // Setup the acceptor with the server certificate and key
            let mut acceptor = SslAcceptor::mozilla_intermediate_v5(SslMethod::tls()).unwrap();
            acceptor.set_certificate(&certificate).unwrap();
            acceptor.set_private_key(&key).unwrap();
            let acceptor = acceptor.build();

            // Serve a single handshake; failures are asserted client-side
            let (stream, _) = listener.accept().unwrap();
            let _ = acceptor.accept(stream);
        });

        (address, handle)
    }

    /// Generates a self-signed certificate authority for handshake tests.
    fn test_certificate_authority() -> TestCertificate {
        // Setup deterministic certificate identity and validity
        let key = PKey::from_rsa(Rsa::generate(2048).unwrap()).unwrap();
        let mut name = X509NameBuilder::new().unwrap();
        name.append_entry_by_text("CN", "ocg-test-ca").unwrap();
        let name = name.build();
        let not_after = Asn1Time::days_from_now(1).unwrap();
        let not_before = Asn1Time::days_from_now(0).unwrap();
        let serial = BigNum::from_u32(1).unwrap().to_asn1_integer().unwrap();

        // Build and sign a minimal CA certificate
        let mut builder = X509::builder().unwrap();
        builder.set_version(2).unwrap();
        builder.set_serial_number(&serial).unwrap();
        builder.set_subject_name(&name).unwrap();
        builder.set_issuer_name(&name).unwrap();
        builder.set_pubkey(&key).unwrap();
        builder.set_not_after(&not_after).unwrap();
        builder.set_not_before(&not_before).unwrap();
        builder
            .append_extension(BasicConstraints::new().critical().ca().build().unwrap())
            .unwrap();
        builder
            .append_extension(KeyUsage::new().critical().key_cert_sign().build().unwrap())
            .unwrap();
        builder.sign(&key, MessageDigest::sha256()).unwrap();

        TestCertificate {
            certificate: builder.build(),
            key,
        }
    }

    /// Generates a localhost server certificate signed by the given CA.
    fn test_server_certificate(ca: &TestCertificate) -> TestCertificate {
        // Setup the server certificate identity and validity
        let key = PKey::from_rsa(Rsa::generate(2048).unwrap()).unwrap();
        let mut name = X509NameBuilder::new().unwrap();
        name.append_entry_by_text("CN", "localhost").unwrap();
        let name = name.build();
        let not_after = Asn1Time::days_from_now(1).unwrap();
        let not_before = Asn1Time::days_from_now(0).unwrap();
        let serial = BigNum::from_u32(2).unwrap().to_asn1_integer().unwrap();

        // Build and sign a localhost certificate with the CA key
        let mut builder = X509::builder().unwrap();
        builder.set_version(2).unwrap();
        builder.set_serial_number(&serial).unwrap();
        builder.set_subject_name(&name).unwrap();
        builder.set_issuer_name(ca.certificate.subject_name()).unwrap();
        builder.set_pubkey(&key).unwrap();
        builder.set_not_after(&not_after).unwrap();
        builder.set_not_before(&not_before).unwrap();
        let subject_alternative_name = SubjectAlternativeName::new()
            .dns("localhost")
            .build(&builder.x509v3_context(Some(&ca.certificate), None))
            .unwrap();
        builder.append_extension(subject_alternative_name).unwrap();
        builder.sign(&ca.key, MessageDigest::sha256()).unwrap();

        TestCertificate {
            certificate: builder.build(),
            key,
        }
    }

    /// Performs a TLS handshake against the given test server address.
    async fn tls_handshake(
        mut connector: MakeTlsConnector,
        address: SocketAddr,
        hostname: &str,
    ) -> Result<()> {
        let stream = TcpStream::connect(address).await?;
        let tls = <MakeTlsConnector as MakeTlsConnect<TcpStream>>::make_tls_connect(
            &mut connector,
            hostname,
        )?;
        tls.connect(stream)
            .await
            .map_err(|err| anyhow::anyhow!("TLS handshake failed: {err}"))?;

        Ok(())
    }
}
