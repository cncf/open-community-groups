//! Open Badges 3.0 credential construction and signing.

use std::{sync::Arc, time::Duration};

use cached::{Cached, LruCache};
use chrono::{DateTime, SecondsFormat, Utc};
use serde_json::Value;
use tokio::{
    sync::{Mutex, MutexGuard},
    time::timeout,
};
use uuid::Uuid;

use crate::types::badges::UserBadge;

use super::{BadgesManagerError, Result};

/// Maximum signed credential representations retained in memory.
const CREDENTIAL_CACHE_CAPACITY: usize = 256;
/// Maximum wait for the bounded signer during a cold credential burst.
const CREDENTIAL_SIGNING_WAIT: Duration = Duration::from_secs(2);

/// Shared size-bounded cache for immutable signed credentials.
#[derive(Clone)]
pub(super) struct CredentialCache {
    /// Least-recently-used entries shared by manager clones.
    entries: Arc<Mutex<LruCache<Uuid, Value>>>,
    /// Serializes cache misses to bound CPU-intensive JSON-LD signing.
    signing_lock: Arc<Mutex<()>>,
}

impl CredentialCache {
    /// Creates an empty cache with the fixed application capacity.
    pub(super) fn new() -> Self {
        let entries = LruCache::builder()
            .max_size(CREDENTIAL_CACHE_CAPACITY)
            .build()
            .expect("credential cache capacity must be positive");
        Self {
            entries: Arc::new(Mutex::new(entries)),
            signing_lock: Arc::new(Mutex::new(())),
        }
    }

    /// Returns a cached immutable credential by opaque award identifier.
    pub(super) async fn get(&self, user_badge_id: Uuid) -> Option<Value> {
        self.entries.lock().await.cache_get(&user_badge_id).cloned()
    }

    /// Stores an immutable signed credential for subsequent requests.
    pub(super) async fn insert(&self, user_badge_id: Uuid, credential: Value) {
        self.entries.lock().await.cache_set(user_badge_id, credential);
    }

    /// Acquires the bounded signing lock or rejects an overloaded cold request.
    pub(super) async fn signing_guard(&self) -> Result<MutexGuard<'_, ()>> {
        timeout(CREDENTIAL_SIGNING_WAIT, self.signing_lock.lock())
            .await
            .map_err(|_| BadgesManagerError::Busy)
    }
}

/// Inputs used to issue an immutable Open Badges credential.
pub(crate) struct CredentialInput<'a> {
    /// Durable award state and immutable snapshot.
    pub award: &'a UserBadge,
    /// Proof creation time.
    pub created_at: DateTime<Utc>,
}

/// Extract a required string from a credential JSON object.
pub(super) fn required_string<'a>(value: &'a Value, pointer: &str) -> Result<&'a str> {
    value
        .pointer(pointer)
        .and_then(Value::as_str)
        .ok_or(BadgesManagerError::InvalidCredential)
}

/// Serialize timestamps consistently for credentials and proofs.
pub(crate) fn rfc3339(value: DateTime<Utc>) -> String {
    value.to_rfc3339_opts(SecondsFormat::Millis, true)
}
