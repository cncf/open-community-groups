//! Sharded in-memory GCRA store keyed by client.

use std::{
    collections::HashMap,
    hash::{BuildHasher, Hash, RandomState},
    sync::{
        Mutex, MutexGuard, PoisonError,
        atomic::{AtomicU64, Ordering},
    },
    time::{Duration, Instant},
};

use crate::config::RateLimitBudget;

#[cfg(test)]
mod tests;

/// Nanoseconds in one second.
const NANOS_PER_SEC: u64 = 1_000_000_000;

/// Minimum time between two purges of expired entries in one shard, in nanoseconds.
const PURGE_INTERVAL_NS: u64 = NANOS_PER_SEC;

/// Number of shards in each store.
const SHARDS: usize = 16;

/// Maximum number of keys tracked by each store across all its shards.
const STORE_CAPACITY: usize = 50_000;

/// Bounded, sharded store applying one GCRA budget to many keys.
///
/// Each key holds a single theoretical arrival time. A key whose stored time
/// is at or before the current time behaves exactly like a missing key, so
/// correctness never depends on removing expired entries.
pub(super) struct KeyedLimiter<K> {
    /// Number of entries evicted to make room for new keys since the last take.
    evictions: AtomicU64,
    /// Algorithm parameters derived from the budget.
    gcra: Gcra,
    /// Behaviour when a new key arrives at a shard that is still full after a purge.
    on_full: OnFull,
    /// Maximum number of keys tracked by each shard.
    shard_capacity: usize,
    /// Process-random hasher selecting the shard of a key.
    shard_hasher: RandomState,
    /// Independently locked partitions of the key space.
    shards: Box<[Mutex<Shard<K>>]>,
}

impl<K: Copy + Eq + Hash> KeyedLimiter<K> {
    /// Creates a store with the production shape for the given budget.
    pub(super) fn new(budget: RateLimitBudget, on_full: OnFull) -> Self {
        Self::with_shape(budget, on_full, SHARDS, STORE_CAPACITY / SHARDS)
    }

    /// Applies one request for `key` at `now_ns` and returns the decision.
    ///
    /// A denial leaves the key's state unchanged. A new key arriving at a full
    /// shard first triggers a throttled purge of expired entries, then is
    /// handled according to the store's [`OnFull`] policy.
    pub(super) fn acquire(&self, key: K, now_ns: u64) -> Decision {
        let mut shard = self.shard(&key);

        // Apply the request to the stored state, treating a missing key as fully refilled
        let stored_ns = shard.entries.get(&key).copied();
        let tat_ns = match self.gcra.acquire(stored_ns.unwrap_or(0), now_ns) {
            Ok(tat_ns) => tat_ns,
            Err(retry_after) => return Decision::Denied { retry_after },
        };
        let allowed = Decision::Allowed {
            used_pct: self.gcra.used_pct(tat_ns, now_ns),
        };

        // Update a tracked key, or track a new one while the shard has room
        if stored_ns.is_some() || shard.entries.len() < self.shard_capacity {
            shard.entries.insert(key, tat_ns);
            return allowed;
        }

        // Make room by dropping entries that no longer carry any penalty
        shard.purge_expired(now_ns);
        if shard.entries.len() < self.shard_capacity {
            shard.entries.insert(key, tat_ns);
            return allowed;
        }

        // Apply the full-shard policy
        match self.on_full {
            OnFull::AllowUntracked => Decision::Untracked,
            OnFull::EvictLeastPenalised => {
                if shard.evict_least_penalised() {
                    self.evictions.fetch_add(1, Ordering::Relaxed);
                }
                shard.entries.insert(key, tat_ns);
                allowed
            }
        }
    }

    /// Returns one token to `key`.
    ///
    /// Refunding a missing key is a no-op. A refund never banks credit beyond
    /// a full burst, because a stored time at or before the current time is
    /// treated as fully refilled.
    pub(super) fn refund(&self, key: &K) {
        let mut shard = self.shard(key);
        if let Some(tat_ns) = shard.entries.get_mut(key) {
            *tat_ns = self.gcra.refund(*tat_ns);
        }
    }

    /// Returns the number of entries evicted since the previous call and resets it.
    ///
    /// Only stores using [`OnFull::EvictLeastPenalised`] evict entries.
    pub(super) fn take_evictions(&self) -> u64 {
        self.evictions.swap(0, Ordering::Relaxed)
    }

    /// Locks the shard owning `key`, recovering the lock if it was poisoned.
    ///
    /// Recovery is safe because each entry is a single integer that is never
    /// left partially updated.
    fn shard(&self, key: &K) -> MutexGuard<'_, Shard<K>> {
        // Truncating the hash on narrower targets keeps it uniformly distributed
        #[allow(clippy::cast_possible_truncation)]
        let index = self.shard_hasher.hash_one(key) as usize % self.shards.len();
        self.shards[index].lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// Creates a store with an explicit number of shards and per-shard capacity.
    fn with_shape(
        budget: RateLimitBudget,
        on_full: OnFull,
        shard_count: usize,
        shard_capacity: usize,
    ) -> Self {
        let shards = (0..shard_count.max(1)).map(|_| Mutex::new(Shard::new())).collect();
        Self {
            evictions: AtomicU64::new(0),
            gcra: Gcra::new(budget),
            on_full,
            shard_capacity,
            shard_hasher: RandomState::new(),
            shards,
        }
    }
}

/// Outcome of applying one request to a key.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum Decision {
    /// The request is within the budget and was recorded.
    Allowed {
        /// Share of the burst in use after this request, from 0 to 100.
        used_pct: u8,
    },
    /// The request exceeds the budget and was not recorded.
    Denied {
        /// Time until the next request for the key would be allowed.
        retry_after: Duration,
    },
    /// The request was allowed without tracking because the store is full.
    Untracked,
}

/// Behaviour for a new key when its shard is still full after a purge.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum OnFull {
    /// Allows the request without tracking the key.
    AllowUntracked,
    /// Evicts the entry closest to a full refill and tracks the new key.
    EvictLeastPenalised,
}

/// Generic cell rate algorithm parameters for one budget.
///
/// State is a theoretical arrival time in nanoseconds since a process epoch.
/// All arithmetic saturates.
#[derive(Debug, Clone, Copy)]
struct Gcra {
    /// Time to refill one token, in nanoseconds.
    interval_ns: u64,
    /// Time to refill the whole burst, in nanoseconds.
    tolerance_ns: u64,
}

impl Gcra {
    /// Derives the algorithm parameters from a budget.
    fn new(budget: RateLimitBudget) -> Self {
        let burst = u64::from(budget.burst.max(1));
        let period_ns = budget.period_secs.saturating_mul(NANOS_PER_SEC);
        let interval_ns = (period_ns / burst).max(1);
        Self {
            interval_ns,
            tolerance_ns: interval_ns.saturating_mul(burst),
        }
    }

    /// Applies one request to `tat_ns` at `now_ns`.
    ///
    /// Returns the new theoretical arrival time when allowed, or the time until
    /// the next request would be allowed when denied.
    fn acquire(&self, tat_ns: u64, now_ns: u64) -> Result<u64, Duration> {
        let new_tat_ns = tat_ns.max(now_ns).saturating_add(self.interval_ns);
        let ahead_ns = new_tat_ns.saturating_sub(now_ns);
        if ahead_ns <= self.tolerance_ns {
            Ok(new_tat_ns)
        } else {
            Err(Duration::from_nanos(ahead_ns - self.tolerance_ns))
        }
    }

    /// Returns `tat_ns` with one token given back.
    fn refund(&self, tat_ns: u64) -> u64 {
        tat_ns.saturating_sub(self.interval_ns)
    }

    /// Returns the share of the burst in use at `now_ns`, from 0 to 100.
    fn used_pct(&self, tat_ns: u64, now_ns: u64) -> u8 {
        let used_ns = u128::from(tat_ns.saturating_sub(now_ns));
        let pct = (used_ns * 100 / u128::from(self.tolerance_ns)).min(100);
        u8::try_from(pct).unwrap_or(100)
    }
}

/// One independently locked partition of a store.
struct Shard<K> {
    /// Theoretical arrival time per key, in nanoseconds since the process epoch.
    entries: HashMap<K, u64>,

    /// Time of the last purge of expired entries, in nanoseconds since the process epoch.
    last_purge_ns: Option<u64>,
}

impl<K: Copy + Eq + Hash> Shard<K> {
    /// Creates an empty shard that allocates only when its first key arrives.
    fn new() -> Self {
        Self {
            entries: HashMap::new(),
            last_purge_ns: None,
        }
    }

    /// Removes the entry with the smallest stored time and reports whether one existed.
    ///
    /// The smallest stored time is the entry closest to a full refill.
    fn evict_least_penalised(&mut self) -> bool {
        let victim = self
            .entries
            .iter()
            .min_by_key(|&(_, tat_ns)| *tat_ns)
            .map(|(key, _)| *key);
        victim.is_some_and(|key| self.entries.remove(&key).is_some())
    }

    /// Removes the entries at or before `now_ns`, at most once per purge interval.
    ///
    /// Removing them loses nothing, since such an entry behaves like a missing key.
    fn purge_expired(&mut self, now_ns: u64) {
        // Throttle purges using the caller's clock
        if let Some(last_purge_ns) = self.last_purge_ns
            && now_ns.saturating_sub(last_purge_ns) < PURGE_INTERVAL_NS
        {
            return;
        }
        self.last_purge_ns = Some(now_ns);

        // Drop the entries that are fully refilled
        self.entries.retain(|_, tat_ns| *tat_ns > now_ns);
    }
}

/// Returns the nanoseconds elapsed from `epoch` to `now`.
///
/// A time before the epoch saturates to zero and an elapsed time beyond
/// `u64::MAX` nanoseconds saturates to `u64::MAX`.
pub(super) fn nanos_since(epoch: Instant, now: Instant) -> u64 {
    u64::try_from(now.saturating_duration_since(epoch).as_nanos()).unwrap_or(u64::MAX)
}
