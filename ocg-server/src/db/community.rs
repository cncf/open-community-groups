//! This module defines some database functionality for the community site.

use std::future::Future;

use anyhow::Result;
use async_trait::async_trait;
use cached::cached;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::{PgClient, PgExecutor, cache_probe},
    types::{
        community::CommunityStats,
        event::{EventKind, EventSummary},
        group::GroupSummary,
    },
};

/// Database trait defining all data access operations for the community site.
#[async_trait]
pub(crate) trait DBCommunity {
    /// Resolves a community ID from the provided community name.
    ///
    /// Positive matches are cached for up to one day per process; misses are
    /// not cached.
    async fn get_community_id_by_name(&self, name: &str) -> Result<Option<Uuid>>;

    /// Retrieves the most recently added groups in the community.
    async fn get_community_recently_added_groups(
        &self,
        community_id: Uuid,
    ) -> Result<Vec<GroupSummary>>;

    /// Retrieves statistical data for the community page.
    ///
    /// Cached for up to one hour per process.
    async fn get_community_site_stats(&self, community_id: Uuid) -> Result<CommunityStats>;

    /// Retrieves upcoming events for the community.
    async fn get_community_upcoming_events(
        &self,
        community_id: Uuid,
        event_kinds: Vec<EventKind>,
    ) -> Result<Vec<EventSummary>>;
}

#[async_trait]
impl<T> DBCommunity for T
where
    T: PgExecutor + Send + Sync,
{
    /// [`DBCommunity::get_community_id_by_name`].
    #[instrument(skip(self), err)]
    async fn get_community_id_by_name(&self, name: &str) -> Result<Option<Uuid>> {
        resolve_community_id(
            name,
            self.use_cache(),
            || self.client(),
            |db| async move {
                db.fetch_scalar_opt("select get_community_id_by_name($1::text)", &[&name])
                    .await
            },
        )
        .await
    }

    /// [`DB::get_community_recently_added_groups`]
    #[instrument(skip(self), err)]
    async fn get_community_recently_added_groups(
        &self,
        community_id: Uuid,
    ) -> Result<Vec<GroupSummary>> {
        self.fetch_json_one(
            "select get_community_recently_added_groups($1::uuid)",
            &[&community_id],
        )
        .await
    }

    /// [`DB::get_community_site_stats`]
    #[instrument(skip(self), err)]
    async fn get_community_site_stats(&self, community_id: Uuid) -> Result<CommunityStats> {
        async fn fetch(db: &PgClient<'_>, community_id: Uuid) -> Result<CommunityStats> {
            db.fetch_json_one(
                "select get_community_site_stats($1::uuid)",
                &[&community_id],
            )
            .await
        }

        #[cached(
            max_size = 1_000,
            ttl_secs = 3600,
            key = "Uuid",
            convert = r#"{ community_id }"#,
            sync_writes = "by_key"
        )]
        async fn inner(db: &PgClient<'_>, community_id: Uuid) -> Result<CommunityStats> {
            fetch(db, community_id).await
        }

        // Bypass process-wide caches outside root pooled handles
        if !self.use_cache() {
            let db = self.client().await?;
            return fetch(&db, community_id).await;
        }

        // Serve a fresh cached value without checking out a client
        if let Some(stats) = cache_probe(&INNER, &community_id).await {
            return Ok(stats);
        }

        // Check out the client before the cached fill takes its key lock
        let db = self.client().await?;
        inner(&db, community_id).await
    }

    /// [`DB::get_community_upcoming_events`]
    #[instrument(skip(self), err)]
    async fn get_community_upcoming_events(
        &self,
        community_id: Uuid,
        event_kinds: Vec<EventKind>,
    ) -> Result<Vec<EventSummary>> {
        let event_kinds = event_kinds.into_iter().map(|k| k.to_string()).collect::<Vec<_>>();
        self.fetch_json_one(
            "select get_community_upcoming_events($1::uuid, $2::text[])",
            &[&community_id, &event_kinds],
        )
        .await
    }
}

// Helpers.

/// Internal lookup error separating a cache-bypassing miss from a database failure.
enum CommunityLookupError {
    /// Community name did not match any row.
    NotFound,
    /// Underlying database lookup failed.
    Other(anyhow::Error),
}

/// Resolves a community ID by name through the positive-only cache.
///
/// Missing communities map to `Err(CommunityLookupError::NotFound)` so
/// `#[cached]` stores only positive matches and never caches misses.
/// `sync_writes` is deliberately omitted: because misses are never stored,
/// single-flighting by key would serialize concurrent requests for the same
/// missing slug while each caller holds a pooled database connection.
#[cached(
    max_size = 1_000,
    ttl_secs = 86400,
    key = "String",
    convert = r#"{ String::from(name) }"#
)]
async fn lookup_community_id<F, Fut>(
    name: &str,
    fetch: F,
) -> std::result::Result<Uuid, CommunityLookupError>
where
    F: FnOnce() -> Fut,
    Fut: Future<Output = Result<Option<Uuid>>>,
{
    // `name` is used by the `#[cached]` key conversion; map misses to an error
    // variant so the cache skips storing them
    let _ = name;
    match fetch().await {
        Ok(Some(community_id)) => Ok(community_id),
        Ok(None) => Err(CommunityLookupError::NotFound),
        Err(err) => Err(CommunityLookupError::Other(err)),
    }
}

/// Resolves a community ID by name, bypassing the cache when `use_cache` is
/// `false` and otherwise probing the cache before acquiring a client and
/// storing only positive matches.
async fn resolve_community_id<A, AFut, C, F, Fut>(
    name: &str,
    use_cache: bool,
    acquire: A,
    fetch: F,
) -> Result<Option<Uuid>>
where
    A: FnOnce() -> AFut,
    AFut: Future<Output = Result<C>>,
    F: FnOnce(C) -> Fut,
    Fut: Future<Output = Result<Option<Uuid>>>,
{
    // Short-circuit empty names without probing or querying
    if name.is_empty() {
        return Ok(None);
    }

    // Bypass the process-wide cache outside root pooled handles
    if !use_cache {
        let client = acquire().await?;
        return fetch(client).await;
    }

    // Serve a fresh cached value without checking out a client
    if let Some(community_id) = cache_probe(&LOOKUP_COMMUNITY_ID, name).await {
        return Ok(Some(community_id));
    }

    // Check out the client and perform the positive-only cached lookup
    let client = acquire().await?;
    match lookup_community_id(name, || fetch(client)).await {
        Ok(community_id) => Ok(Some(community_id)),
        Err(CommunityLookupError::NotFound) => Ok(None),
        Err(CommunityLookupError::Other(err)) => Err(err),
    }
}

#[cfg(test)]
mod tests {
    use std::{
        sync::{
            Arc,
            atomic::{AtomicUsize, Ordering},
        },
        time::Duration,
    };

    use anyhow::anyhow;
    use cached::Cached;
    use tokio::{
        sync::{Barrier, Mutex},
        time::timeout,
    };
    use uuid::Uuid;

    use super::*;

    /// Serializes tests that share the process-wide community ID cache.
    static CACHE_TEST_LOCK: Mutex<()> = Mutex::const_new(());

    #[tokio::test]
    async fn test_resolve_community_id_bounds_positive_cache_size() {
        // Isolate the shared cache for this test
        let _guard = CACHE_TEST_LOCK.lock().await;
        clear_community_id_cache().await;

        // Populate more distinct valid communities than the cache max_size
        for index in 0..1_050usize {
            let slug = format!("community-{index}");
            let community_id = Uuid::from_u128(index as u128 + 1);
            let resolved = resolve_community_id(
                &slug,
                true,
                || async { Ok(()) },
                |()| async move { Ok(Some(community_id)) },
            )
            .await
            .expect("lookup to succeed");
            assert_eq!(resolved, Some(community_id));
        }

        // Check the cache size stays within the configured bound
        let cache_size = LOOKUP_COMMUNITY_ID.read().await.cache_size();
        assert_eq!(cache_size, 1_000);
    }

    #[tokio::test]
    async fn test_resolve_community_id_bypasses_cache_when_disabled() {
        // Isolate the shared cache for this test
        let _guard = CACHE_TEST_LOCK.lock().await;
        clear_community_id_cache().await;
        let cached_id = Uuid::from_u128(10);
        let uncached_id = Uuid::from_u128(11);
        let tx_id = Uuid::from_u128(12);

        // Run an uncached lookup first and check it does not populate the cache
        let resolved = resolve_community_id(
            "tx-only-community",
            false,
            || async { Ok(()) },
            |()| async move { Ok(Some(uncached_id)) },
        )
        .await
        .expect("uncached lookup to succeed");
        assert_eq!(resolved, Some(uncached_id));
        assert_eq!(LOOKUP_COMMUNITY_ID.read().await.cache_size(), 0);

        // Warm the cache for a slug through the cached path
        let seeded = resolve_community_id(
            "cncf",
            true,
            || async { Ok(()) },
            |()| async move { Ok(Some(cached_id)) },
        )
        .await
        .expect("cached lookup to succeed");
        assert_eq!(seeded, Some(cached_id));

        // Run an uncached lookup for the warmed slug and check it bypasses both reading and writing
        let bypassed = resolve_community_id(
            "cncf",
            false,
            || async { Ok(()) },
            |()| async move { Ok(Some(tx_id)) },
        )
        .await
        .expect("bypassed lookup to succeed");
        assert_eq!(bypassed, Some(tx_id));
        assert_eq!(
            cache_probe(&LOOKUP_COMMUNITY_ID, "cncf").await,
            Some(cached_id)
        );
    }

    #[tokio::test]
    async fn test_resolve_community_id_caches_newly_created_community_after_miss() {
        // Isolate the shared cache for this test
        let _guard = CACHE_TEST_LOCK.lock().await;
        clear_community_id_cache().await;
        let community_id = Uuid::from_u128(42);
        let calls = Arc::new(AtomicUsize::new(0));

        // First lookup misses before the community exists
        let first = resolve_community_id(
            "new-community",
            true,
            || async { Ok(()) },
            |()| {
                let calls = calls.clone();
                async move {
                    calls.fetch_add(1, Ordering::SeqCst);
                    Ok(None)
                }
            },
        )
        .await
        .expect("miss lookup to succeed");
        assert_eq!(first, None);
        assert_eq!(calls.load(Ordering::SeqCst), 1);

        // Second lookup sees the newly created community immediately
        let second = resolve_community_id(
            "new-community",
            true,
            || async { Ok(()) },
            |()| {
                let calls = calls.clone();
                async move {
                    calls.fetch_add(1, Ordering::SeqCst);
                    Ok(Some(community_id))
                }
            },
        )
        .await
        .expect("positive lookup to succeed");
        assert_eq!(second, Some(community_id));
        assert_eq!(calls.load(Ordering::SeqCst), 2);

        // Third lookup hits the positive cache without acquiring a client
        let third = resolve_community_id(
            "new-community",
            true,
            || async { Err::<(), _>(anyhow!("client must not be acquired on cache hit")) },
            |()| async { panic!("fetch must not run on cache hit") },
        )
        .await
        .expect("cached lookup to succeed");
        assert_eq!(third, Some(community_id));
        assert_eq!(calls.load(Ordering::SeqCst), 2);
    }

    #[tokio::test]
    async fn test_resolve_community_id_concurrent_misses_run_in_parallel() {
        // Isolate the shared cache and synchronize two concurrent misses on a barrier
        let _guard = CACHE_TEST_LOCK.lock().await;
        clear_community_id_cache().await;
        let barrier = Arc::new(Barrier::new(2));

        // Run two lookups for the same missing slug concurrently; serialization would deadlock
        let (first, second) = timeout(Duration::from_secs(1), async {
            tokio::join!(
                resolve_community_id(
                    "missing-concurrent",
                    true,
                    || async { Ok(()) },
                    |()| {
                        let barrier = barrier.clone();
                        async move {
                            barrier.wait().await;
                            Ok(None)
                        }
                    },
                ),
                resolve_community_id(
                    "missing-concurrent",
                    true,
                    || async { Ok(()) },
                    |()| {
                        let barrier = barrier.clone();
                        async move {
                            barrier.wait().await;
                            Ok(None)
                        }
                    },
                ),
            )
        })
        .await
        .expect("concurrent misses not to serialize behind a key lock");

        // Check both lookups returned None and left the cache empty
        assert_eq!(first.expect("first lookup to succeed"), None);
        assert_eq!(second.expect("second lookup to succeed"), None);
        assert_eq!(LOOKUP_COMMUNITY_ID.read().await.cache_size(), 0);
    }

    #[tokio::test]
    async fn test_resolve_community_id_ignores_404_flood_without_evicting_valid_entries() {
        // Isolate the shared cache and seed one valid community
        let _guard = CACHE_TEST_LOCK.lock().await;
        clear_community_id_cache().await;
        let valid_id = Uuid::from_u128(1);
        let seeded = resolve_community_id(
            "cncf",
            true,
            || async { Ok(()) },
            |()| async move { Ok(Some(valid_id)) },
        )
        .await
        .expect("valid community lookup to succeed");
        assert_eq!(seeded, Some(valid_id));
        assert_eq!(LOOKUP_COMMUNITY_ID.read().await.cache_size(), 1);

        // Flood with more missing slugs than the cache capacity
        for index in 0..2_000usize {
            let missing_slug = format!("missing-community-{index}");
            let result = resolve_community_id(
                &missing_slug,
                true,
                || async { Ok(()) },
                |()| async { Ok(None) },
            )
            .await
            .expect("missing lookup to succeed");
            assert_eq!(result, None);
        }

        // Check misses never populated the cache or evicted the valid community
        assert_eq!(LOOKUP_COMMUNITY_ID.read().await.cache_size(), 1);
        assert_eq!(
            cache_probe(&LOOKUP_COMMUNITY_ID, "missing-community-0").await,
            None
        );
        let cached = resolve_community_id(
            "cncf",
            true,
            || async { Err::<(), _>(anyhow!("client must not be acquired on cache hit")) },
            |()| async { panic!("fetch must not run for non-evicted community") },
        )
        .await
        .expect("cached community lookup to succeed");
        assert_eq!(cached, Some(valid_id));
    }

    #[tokio::test]
    async fn test_resolve_community_id_propagates_client_checkout_errors() {
        // Isolate the shared cache for this test
        let _guard = CACHE_TEST_LOCK.lock().await;
        clear_community_id_cache().await;

        // Fail client checkout before reaching the cached lookup
        let err = resolve_community_id(
            "pool-exhausted",
            true,
            || async { Err::<(), _>(anyhow!("pool wait timed out")) },
            |()| async { panic!("fetch must not run when client checkout fails") },
        )
        .await
        .expect_err("client checkout failure to propagate");

        // Check error propagates and cache remains empty
        assert!(err.to_string().contains("pool wait timed out"));
        assert_eq!(LOOKUP_COMMUNITY_ID.read().await.cache_size(), 0);
    }

    #[tokio::test]
    async fn test_resolve_community_id_propagates_errors_without_caching() {
        // Isolate the shared cache for this test
        let _guard = CACHE_TEST_LOCK.lock().await;
        clear_community_id_cache().await;
        let community_id = Uuid::from_u128(7);

        // Fail the first lookup with a database error
        let err = resolve_community_id(
            "flaky-community",
            true,
            || async { Ok(()) },
            |()| async { Err(anyhow!("database unavailable")) },
        )
        .await
        .expect_err("database failure to propagate");
        assert!(err.to_string().contains("database unavailable"));
        assert_eq!(LOOKUP_COMMUNITY_ID.read().await.cache_size(), 0);

        // Subsequent lookup retries and caches the positive result
        let recovered = resolve_community_id(
            "flaky-community",
            true,
            || async { Ok(()) },
            |()| async move { Ok(Some(community_id)) },
        )
        .await
        .expect("retry lookup to succeed");
        assert_eq!(recovered, Some(community_id));
        assert_eq!(LOOKUP_COMMUNITY_ID.read().await.cache_size(), 1);
    }

    #[tokio::test]
    async fn test_resolve_community_id_short_circuits_empty_name() {
        // Isolate the shared cache for this test
        let _guard = CACHE_TEST_LOCK.lock().await;
        clear_community_id_cache().await;

        // Empty name returns None without acquiring a client or touching the cache
        let result = resolve_community_id(
            "",
            true,
            || async { Err::<(), _>(anyhow!("client must not be acquired for empty name")) },
            |()| async { panic!("fetch must not run for empty name") },
        )
        .await
        .expect("empty name lookup to succeed");
        assert_eq!(result, None);
        assert_eq!(LOOKUP_COMMUNITY_ID.read().await.cache_size(), 0);
    }

    // Helpers.

    /// Clears the shared community ID cache between tests.
    async fn clear_community_id_cache() {
        LOOKUP_COMMUNITY_ID.write().await.cache_clear();
    }
}
