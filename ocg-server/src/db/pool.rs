//! Database pool configuration helpers.

use std::time::Duration;

use deadpool_postgres::{Config as DeadpoolDbConfig, ManagerConfig, PoolConfig, RecyclingMethod};

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
/// session defaults, so they survive `DISCARD ALL` when connections are recycled.
const DB_SESSION_OPTIONS: &str =
    "-c statement_timeout=30000 -c idle_in_transaction_session_timeout=60000";

/// Apply server defaults to the database pool configuration.
pub(crate) fn config_with_defaults(cfg: &DeadpoolDbConfig) -> DeadpoolDbConfig {
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
            recycling_method: RecyclingMethod::Clean,
        });
        cfg.options = Some("-c statement_timeout=5000".to_string());
        cfg.pool = Some(PoolConfig::new(32));

        let pool = cfg.pool.as_mut().expect("pool config should be set");
        pool.timeouts.create = Some(Duration::from_secs(12));
        pool.timeouts.recycle = Some(Duration::from_secs(11));
        pool.timeouts.wait = Some(Duration::from_secs(10));

        let cfg = config_with_defaults(&cfg);

        let manager = cfg.manager.expect("manager config should be set");
        assert_eq!(manager.recycling_method, RecyclingMethod::Clean);
        assert_eq!(cfg.options.as_deref(), Some("-c statement_timeout=5000"));

        let pool = cfg.pool.expect("pool config should be set");
        assert_eq!(pool.max_size, 32);
        assert_eq!(pool.timeouts.create, Some(Duration::from_secs(12)));
        assert_eq!(pool.timeouts.recycle, Some(Duration::from_secs(11)));
        assert_eq!(pool.timeouts.wait, Some(Duration::from_secs(10)));
    }
}
