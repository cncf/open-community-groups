//! Revocation-only Bitstring Status List profile.

use std::{
    collections::HashMap,
    io::Write,
    sync::{Arc, Mutex as StdMutex, PoisonError, Weak},
    time::Duration,
};

use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use cached::{Cached, LruCache};
use flate2::{Compression, write::GzEncoder};
use serde_json::Value;
use tokio::{
    sync::{Mutex, OwnedMutexGuard},
    time::timeout,
};
use uuid::Uuid;

use super::{BadgesManagerError, Result};

#[cfg(test)]
mod tests;

/// Maximum signed status-list representations retained in memory.
const STATUS_LIST_CACHE_CAPACITY: usize = 256;

/// Number of entries published by each status list.
pub(crate) const STATUS_LIST_ENTRIES: usize = 131_072;

/// Maximum wait for a per-list signer during a cold status-list burst.
const STATUS_LIST_SIGNING_WAIT: Duration = Duration::from_secs(2);

/// Required uncompressed status list size.
pub(crate) const STATUS_LIST_SIZE: usize = STATUS_LIST_ENTRIES / 8;

/// Required credential subject TTL in milliseconds.
pub(crate) const STATUS_LIST_TTL_MS: u64 = 600_000;

/// Per-status-list weak lock map keeping memory bounded to active signers.
type SigningLockMap = Arc<StdMutex<HashMap<Uuid, Weak<Mutex<()>>>>>;

/// One signed representation and the exact state it covers.
#[derive(Clone)]
struct CachedStatusList {
    /// Signed status-list credential.
    credential: Value,
    /// Issuing group bound to the status-list identifier.
    group_id: Uuid,
    /// Revocation indexes represented by the credential.
    revoked_indexes: Vec<i32>,
}

/// Cleanup guard removing an idle status-list lock entry on drop.
struct SigningLockCleanup {
    /// Identifier of the status list whose lock entry may be removed.
    badge_status_list_id: Uuid,
    /// Shared per-list lock table.
    signing_locks: SigningLockMap,
}

impl Drop for SigningLockCleanup {
    fn drop(&mut self) {
        // Remove the table entry only when no holder or waiter retains the lock
        let mut signing_locks = self.signing_locks.lock().unwrap_or_else(PoisonError::into_inner);
        if signing_locks
            .get(&self.badge_status_list_id)
            .is_some_and(|lock| lock.strong_count() == 0)
        {
            signing_locks.remove(&self.badge_status_list_id);
        }
    }
}

/// Shared size-bounded cache for signed status-list representations.
#[derive(Clone)]
pub(super) struct StatusListCache {
    /// Least-recently-used entries shared by manager clones.
    entries: Arc<Mutex<LruCache<Uuid, CachedStatusList>>>,
    /// Per-list signing locks so signing one list never blocks unrelated lists.
    signing_locks: SigningLockMap,
}

impl StatusListCache {
    /// Creates an empty cache with the fixed application capacity.
    pub(super) fn new() -> Self {
        let entries = LruCache::builder()
            .max_size(STATUS_LIST_CACHE_CAPACITY)
            .build()
            .expect("status-list cache capacity must be positive");
        Self {
            entries: Arc::new(Mutex::new(entries)),
            signing_locks: Arc::new(StdMutex::new(HashMap::new())),
        }
    }

    /// Returns a representation only when it covers the exact current state.
    pub(super) async fn get(
        &self,
        badge_status_list_id: Uuid,
        group_id: Uuid,
        revoked_indexes: &[i32],
    ) -> Option<Value> {
        let mut entries = self.entries.lock().await;
        entries
            .cache_get(&badge_status_list_id)
            .filter(|entry| entry.group_id == group_id && entry.revoked_indexes == revoked_indexes)
            .map(|entry| entry.credential.clone())
    }

    /// Stores the newest signed representation for one status-list identifier.
    pub(super) async fn insert(
        &self,
        badge_status_list_id: Uuid,
        credential: Value,
        group_id: Uuid,
        revoked_indexes: &[i32],
    ) {
        self.entries.lock().await.cache_set(
            badge_status_list_id,
            CachedStatusList {
                credential,
                group_id,
                revoked_indexes: revoked_indexes.to_vec(),
            },
        );
    }

    /// Acquires the bounded per-list miss lock before signing changed state.
    pub(super) async fn signing_guard(
        &self,
        badge_status_list_id: Uuid,
    ) -> Result<StatusListSigningGuard> {
        // Declare cleanup before the lock so timeout or cancellation drops the
        // strong lock handle before checking whether the table entry is idle
        let lock_cleanup = SigningLockCleanup {
            badge_status_list_id,
            signing_locks: Arc::clone(&self.signing_locks),
        };
        let lock = self.signing_lock(badge_status_list_id);

        // Wait up to the fixed bound for any in-flight signer of the same list
        let guard = timeout(STATUS_LIST_SIGNING_WAIT, lock.lock_owned())
            .await
            .map_err(|_| BadgesManagerError::Busy)?;

        Ok(StatusListSigningGuard {
            _guard: guard,
            _lock_cleanup: lock_cleanup,
        })
    }

    /// Returns the number of per-list lock entries currently tracked.
    #[cfg(test)]
    pub(super) fn signing_locks_len(&self) -> usize {
        self.signing_locks
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .len()
    }

    /// Returns the shared signing mutex for one status-list identifier.
    fn signing_lock(&self, badge_status_list_id: Uuid) -> Arc<Mutex<()>> {
        let mut signing_locks = self.signing_locks.lock().unwrap_or_else(PoisonError::into_inner);
        if let Some(lock) = signing_locks.get(&badge_status_list_id).and_then(Weak::upgrade) {
            return lock;
        }

        // Allocate a fresh per-list mutex and keep only a weak table reference
        let lock = Arc::new(Mutex::new(()));
        signing_locks.insert(badge_status_list_id, Arc::downgrade(&lock));
        lock
    }
}

/// Guard holding one per-status-list signing lock until signing completes.
pub(super) struct StatusListSigningGuard {
    /// Owned mutex guard kept alive for the duration of signing.
    ///
    /// Declared before `_lock_cleanup` so the per-list lock releases its strong
    /// reference before cleanup checks whether the table entry is idle.
    _guard: OwnedMutexGuard<()>,
    /// Removes the per-list lock entry once no holder or waiter remains.
    _lock_cleanup: SigningLockCleanup,
}

/// Encodes revoked indexes as a gzip-compressed multibase base64url bitstring.
pub(super) fn encode_status_list(revoked_indexes: &[i32]) -> Result<String> {
    // Set every bounded index using the status-list MSB bit orientation
    let mut bytes = vec![0_u8; STATUS_LIST_SIZE];
    for index in revoked_indexes {
        let index = usize::try_from(*index).map_err(|_| BadgesManagerError::InvalidStatusList)?;
        if index >= STATUS_LIST_ENTRIES {
            return Err(BadgesManagerError::InvalidStatusList);
        }
        bytes[index / 8] |= 1 << (7 - index % 8);
    }

    // Compress and encode the exact byte sequence using the required multibase prefix
    let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
    encoder
        .write_all(&bytes)
        .map_err(|_| BadgesManagerError::InvalidStatusList)?;
    let compressed = encoder.finish().map_err(|_| BadgesManagerError::InvalidStatusList)?;

    Ok(format!("u{}", URL_SAFE_NO_PAD.encode(compressed)))
}
