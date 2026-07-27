//! Revocation-only Bitstring Status List profile.

use std::{io::Write, sync::Arc};

use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use cached::{Cached, LruCache};
use flate2::{Compression, write::GzEncoder};
use serde_json::Value;
use tokio::sync::{Mutex, MutexGuard};
use uuid::Uuid;

use super::{BadgesManagerError, Result};

#[cfg(test)]
mod tests;

/// Maximum signed status-list representations retained in memory.
const STATUS_LIST_CACHE_CAPACITY: usize = 256;

/// Number of entries published by each status list.
pub(crate) const STATUS_LIST_ENTRIES: usize = 131_072;

/// Required uncompressed status list size.
pub(crate) const STATUS_LIST_SIZE: usize = STATUS_LIST_ENTRIES / 8;

/// Required credential subject TTL in milliseconds.
pub(crate) const STATUS_LIST_TTL_MS: u64 = 600_000;

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

/// Shared size-bounded cache for signed status-list representations.
#[derive(Clone)]
pub(super) struct StatusListCache {
    /// Least-recently-used entries shared by manager clones.
    entries: Arc<Mutex<LruCache<Uuid, CachedStatusList>>>,
    /// Serializes cache misses so a cold public burst produces one signature.
    signing_lock: Arc<Mutex<()>>,
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
            signing_lock: Arc::new(Mutex::new(())),
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

    /// Acquires the shared miss lock before signing changed state.
    pub(super) async fn signing_guard(&self) -> MutexGuard<'_, ()> {
        self.signing_lock.lock().await
    }
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
