//! Database pool configuration helpers.

use std::time::Duration;

use deadpool_postgres::{Config, ManagerConfig, PoolConfig, RecyclingMethod};

/// Default maximum number of database connections in the server pool.
const DB_POOL_MAX_SIZE: usize = 25;

/// Default timeout for recycling a database connection.
const DB_POOL_RECYCLE_TIMEOUT: Duration = Duration::from_secs(5);

/// Default timeout when waiting for an available database connection.
const DB_POOL_WAIT_TIMEOUT: Duration = Duration::from_secs(5);

/// SQL used to reset transaction and advisory lock state when recycling a connection.
const DB_RECYCLE_SQL: &str = "ROLLBACK; SELECT pg_advisory_unlock_all();";

/// Apply server defaults to the database pool configuration.
pub(crate) fn config_with_defaults(cfg: &Config) -> Config {
    let mut cfg = cfg.clone();

    // Reset leaked transaction and advisory lock state when recycling connections
    cfg.manager.get_or_insert_with(|| ManagerConfig {
        recycling_method: RecyclingMethod::Custom(DB_RECYCLE_SQL.to_string()),
    });

    // Bound pool capacity and waits when deployment config does not override them
    let pool_cfg = cfg.pool.get_or_insert_with(|| PoolConfig::new(DB_POOL_MAX_SIZE));
    pool_cfg.timeouts.recycle.get_or_insert(DB_POOL_RECYCLE_TIMEOUT);
    pool_cfg.timeouts.wait.get_or_insert(DB_POOL_WAIT_TIMEOUT);

    cfg
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_with_defaults_applies_missing_defaults() {
        let cfg = config_with_defaults(&Config::new());

        let manager = cfg.manager.expect("manager config should be set");
        assert_eq!(
            manager.recycling_method,
            RecyclingMethod::Custom(DB_RECYCLE_SQL.to_string())
        );

        let pool = cfg.pool.expect("pool config should be set");
        assert_eq!(pool.max_size, DB_POOL_MAX_SIZE);
        assert_eq!(pool.timeouts.recycle, Some(DB_POOL_RECYCLE_TIMEOUT));
        assert_eq!(pool.timeouts.wait, Some(DB_POOL_WAIT_TIMEOUT));
    }

    #[test]
    fn config_with_defaults_preserves_configured_values() {
        let mut cfg = Config::new();
        cfg.manager = Some(ManagerConfig {
            recycling_method: RecyclingMethod::Clean,
        });
        cfg.pool = Some(PoolConfig::new(32));

        let pool = cfg.pool.as_mut().expect("pool config should be set");
        pool.timeouts.recycle = Some(Duration::from_secs(11));
        pool.timeouts.wait = Some(Duration::from_secs(10));

        let cfg = config_with_defaults(&cfg);

        let manager = cfg.manager.expect("manager config should be set");
        assert_eq!(manager.recycling_method, RecyclingMethod::Clean);

        let pool = cfg.pool.expect("pool config should be set");
        assert_eq!(pool.max_size, 32);
        assert_eq!(pool.timeouts.recycle, Some(Duration::from_secs(11)));
        assert_eq!(pool.timeouts.wait, Some(Duration::from_secs(10)));
    }
}
