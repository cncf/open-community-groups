//! Database pool configuration helpers.

use std::time::Duration;

use anyhow::{Context, Result};
use deadpool_postgres::{
    Config as DeadpoolDbConfig, Hook, Manager, ManagerConfig, Pool, PoolConfig, RecyclingMethod,
    Runtime,
};
use tokio_postgres::{
    Config as PgConfig, Socket,
    tls::{MakeTlsConnect, TlsConnect},
};

/// Default timeout for establishing a new database connection.
const DB_POOL_CREATE_TIMEOUT: Duration = Duration::from_secs(10);

/// Default maximum number of database connections in the server pool.
const DB_POOL_MAX_SIZE: usize = 25;

/// Default timeout for recycling a database connection.
const DB_POOL_RECYCLE_TIMEOUT: Duration = Duration::from_secs(5);

/// Default timeout when waiting for an available database connection.
const DB_POOL_WAIT_TIMEOUT: Duration = Duration::from_secs(5);

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

/// Create the database pool, applying server defaults to its configuration.
pub(crate) fn create_pool<T>(cfg: &DeadpoolDbConfig, tls: T) -> Result<Pool>
where
    T: MakeTlsConnect<Socket> + Clone + Send + Sync + 'static,
    T::Stream: Send + Sync,
    T::TlsConnect: Send + Sync,
    <T::TlsConnect as TlsConnect<Socket>>::Future: Send,
{
    // Apply the defaults the deployment config leaves unset
    let cfg = config_with_defaults(cfg);
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

/// Apply server defaults to the database pool configuration.
fn config_with_defaults(cfg: &DeadpoolDbConfig) -> DeadpoolDbConfig {
    let mut cfg = cfg.clone();

    // Reset session state when recycling connections
    cfg.manager.get_or_insert(ManagerConfig {
        recycling_method: RecyclingMethod::Clean,
    });

    // Bound statement and idle-transaction time when deployment config does not override it
    cfg.options.get_or_insert_with(|| DB_SESSION_OPTIONS.to_string());

    // Bound pool capacity and waits when deployment config does not override them
    let pool_cfg = cfg.pool.get_or_insert_with(|| PoolConfig::new(DB_POOL_MAX_SIZE));
    pool_cfg.timeouts.create.get_or_insert(DB_POOL_CREATE_TIMEOUT);
    pool_cfg.timeouts.recycle.get_or_insert(DB_POOL_RECYCLE_TIMEOUT);
    pool_cfg.timeouts.wait.get_or_insert(DB_POOL_WAIT_TIMEOUT);

    cfg
}

/// Build the connection configuration, applying server defaults to its socket
/// bounds.
///
/// The pool configuration only carries some of the socket options as fields;
/// the rest can only come from its connection string. The defaults are
/// therefore applied to the resolved connection configuration.
fn pg_config_with_defaults(cfg: &DeadpoolDbConfig) -> Result<PgConfig> {
    let mut pg_cfg = cfg
        .get_pg_config()
        .context("invalid database connection configuration")?;

    // Probe idle connections early when deployment config keeps the driver default
    if pg_cfg.get_keepalives_idle() == PgConfig::new().get_keepalives_idle() {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_with_defaults_applies_missing_defaults() {
        let cfg = config_with_defaults(&DeadpoolDbConfig::new());

        let manager = cfg.manager.expect("manager config should be set");
        assert_eq!(manager.recycling_method, RecyclingMethod::Clean);
        assert_eq!(cfg.options.as_deref(), Some(DB_SESSION_OPTIONS));

        let pool = cfg.pool.expect("pool config should be set");
        assert_eq!(pool.max_size, DB_POOL_MAX_SIZE);
        assert_eq!(pool.timeouts.create, Some(DB_POOL_CREATE_TIMEOUT));
        assert_eq!(pool.timeouts.recycle, Some(DB_POOL_RECYCLE_TIMEOUT));
        assert_eq!(pool.timeouts.wait, Some(DB_POOL_WAIT_TIMEOUT));
    }

    #[test]
    fn test_config_with_defaults_preserves_configured_values() {
        let mut cfg = DeadpoolDbConfig::new();
        cfg.manager = Some(ManagerConfig {
            recycling_method: RecyclingMethod::Fast,
        });
        cfg.options = Some("-c statement_timeout=5000".to_string());
        cfg.pool = Some(PoolConfig::new(32));

        let pool = cfg.pool.as_mut().expect("pool config should be set");
        pool.timeouts.create = Some(Duration::from_secs(12));
        pool.timeouts.recycle = Some(Duration::from_secs(11));
        pool.timeouts.wait = Some(Duration::from_secs(10));

        let cfg = config_with_defaults(&cfg);

        let manager = cfg.manager.expect("manager config should be set");
        assert_eq!(manager.recycling_method, RecyclingMethod::Fast);
        assert_eq!(cfg.options.as_deref(), Some("-c statement_timeout=5000"));

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
        cfg.keepalives_idle = Some(Duration::from_secs(45));
        cfg.url = Some("keepalives_interval=7 keepalives_retries=9 tcp_user_timeout=5".to_string());

        let pg_cfg = pg_config_with_defaults(&cfg).expect("connection config should be valid");

        assert_eq!(pg_cfg.get_keepalives_idle(), Duration::from_secs(45));
        assert_eq!(
            pg_cfg.get_keepalives_interval(),
            Some(Duration::from_secs(7))
        );
        assert_eq!(pg_cfg.get_keepalives_retries(), Some(9));
        assert_eq!(pg_cfg.get_tcp_user_timeout(), Some(&Duration::from_secs(5)));
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
}
