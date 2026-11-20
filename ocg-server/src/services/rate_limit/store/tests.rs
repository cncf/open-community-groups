use std::{
    sync::{
        Arc, Barrier, PoisonError,
        atomic::{AtomicUsize, Ordering},
    },
    thread,
    time::{Duration, Instant},
};

use crate::config::RateLimitBudget;

use super::{Decision, KeyedLimiter, OnFull, nanos_since};

/// One second in nanoseconds.
const SEC: u64 = 1_000_000_000;

#[test]
fn test_keyed_limiter_acquire_allows_burst_exactly_then_denies_for_one_interval() {
    // Setup a store whose interval is ten seconds
    let limiter = KeyedLimiter::new(budget(3, 30), OnFull::AllowUntracked);
    let now_ns = 100 * SEC;

    // Spend the whole burst at once
    let decisions: Vec<_> = (0..3).map(|_| limiter.acquire(1, now_ns)).collect();

    // Check the burst is allowed with growing usage, then the next request is denied
    assert_eq!(
        decisions,
        vec![
            Decision::Allowed { used_pct: 33 },
            Decision::Allowed { used_pct: 66 },
            Decision::Allowed { used_pct: 100 },
        ]
    );
    assert_eq!(
        limiter.acquire(1, now_ns),
        Decision::Denied {
            retry_after: Duration::from_secs(10)
        }
    );
}

#[test]
fn test_keyed_limiter_acquire_concurrent_threads_with_fixed_time_get_exactly_burst() {
    // Setup a production-shaped store and eight threads contending for one key
    let limiter = Arc::new(KeyedLimiter::new(
        budget(1_000, 3_600),
        OnFull::AllowUntracked,
    ));
    let allowed = Arc::new(AtomicUsize::new(0));
    let barrier = Arc::new(Barrier::new(8));
    let now_ns = 100 * SEC;

    // Run more attempts than the burst from every thread at the same time
    thread::scope(|scope| {
        for _ in 0..8 {
            let allowed = allowed.clone();
            let barrier = barrier.clone();
            let limiter = limiter.clone();
            scope.spawn(move || {
                barrier.wait();
                for _ in 0..250 {
                    if matches!(limiter.acquire(7_u32, now_ns), Decision::Allowed { .. }) {
                        allowed.fetch_add(1, Ordering::Relaxed);
                    }
                }
            });
        }
    });

    // Check exactly the burst was allowed across all threads
    assert_eq!(allowed.load(Ordering::Relaxed), 1_000);
    assert!(matches!(
        limiter.acquire(7, now_ns),
        Decision::Denied { .. }
    ));
}

#[test]
fn test_keyed_limiter_acquire_denials_do_not_consume() {
    // Setup an exhausted key with a ten-second interval
    let limiter = KeyedLimiter::new(budget(2, 20), OnFull::AllowUntracked);
    let now_ns = 100 * SEC;
    limiter.acquire(1, now_ns);
    limiter.acquire(1, now_ns);

    // Send several requests over the limit
    let denials: Vec<_> = (0..5).map(|_| limiter.acquire(1, now_ns + SEC)).collect();

    // Check every denial reports the same wait, so none was recorded
    assert!(denials.iter().all(|decision| *decision
        == Decision::Denied {
            retry_after: Duration::from_secs(9)
        }));

    // Check exactly one token is available after one interval
    assert!(matches!(
        limiter.acquire(1, now_ns + 10 * SEC),
        Decision::Allowed { .. }
    ));
    assert!(matches!(
        limiter.acquire(1, now_ns + 10 * SEC),
        Decision::Denied { .. }
    ));
}

#[test]
fn test_keyed_limiter_acquire_evict_policy_evicts_least_penalised_entry() {
    // Setup a full single-shard store with a lightly used key and an exhausted key
    let limiter = KeyedLimiter::with_shape(budget(3, 30), OnFull::EvictLeastPenalised, 1, 2);
    let now_ns = 100 * SEC;
    limiter.acquire(1, now_ns);
    for _ in 0..3 {
        limiter.acquire(2, now_ns);
    }

    // Track a new key while the shard is full of active keys
    let decision = limiter.acquire(3, now_ns);

    // Check the new key is tracked in place of the lightly used key
    assert_eq!(decision, Decision::Allowed { used_pct: 33 });
    assert_eq!(tracked_keys(&limiter), vec![2, 3]);
    assert_eq!(limiter.take_evictions(), 1);
    assert_eq!(limiter.take_evictions(), 0);

    // Check the penalised key stays limited
    assert!(matches!(
        limiter.acquire(2, now_ns),
        Decision::Denied { .. }
    ));

    // Check refunding the evicted key is a no-op
    limiter.refund(&1);
    assert_eq!(tracked_keys(&limiter), vec![2, 3]);
    assert_eq!(stored_ns(&limiter, 2), Some(130 * SEC));
    assert_eq!(stored_ns(&limiter, 3), Some(110 * SEC));
}

#[test]
fn test_keyed_limiter_acquire_full_shard_purges_expired_entries_without_loss() {
    // Setup a full single-shard store with one expired key and one active key
    let limiter = KeyedLimiter::with_shape(budget(1, 10), OnFull::AllowUntracked, 1, 2);
    limiter.acquire(1, 0);
    limiter.acquire(2, 5 * SEC);

    // Track a new key once the first key is fully refilled
    let decision = limiter.acquire(3, 12 * SEC);

    // Check only the expired key was removed and the active key stays limited
    assert_eq!(decision, Decision::Allowed { used_pct: 100 });
    assert_eq!(tracked_keys(&limiter), vec![2, 3]);
    assert_eq!(
        limiter.acquire(2, 12 * SEC),
        Decision::Denied {
            retry_after: Duration::from_secs(3)
        }
    );
    assert_eq!(limiter.take_evictions(), 0);
}

#[test]
fn test_keyed_limiter_acquire_purge_is_throttled_per_shard() {
    // Setup a full single-shard store whose keys refill in half a second
    let limiter = KeyedLimiter::with_shape(budget(2, 1), OnFull::AllowUntracked, 1, 2);
    limiter.acquire(1, 0);
    limiter.acquire(2, 0);

    // Purge while nothing has expired
    assert_eq!(limiter.acquire(3, 0), Decision::Untracked);

    // Check expired entries stay until a second has passed since the last purge
    assert_eq!(limiter.acquire(3, SEC / 2 + 1), Decision::Untracked);
    assert_eq!(tracked_keys(&limiter), vec![1, 2]);
    assert_eq!(limiter.acquire(3, SEC - 1), Decision::Untracked);

    // Check the next purge runs once the throttle interval has elapsed
    assert_eq!(limiter.acquire(3, SEC), Decision::Allowed { used_pct: 50 });
    assert_eq!(tracked_keys(&limiter), vec![3]);
}

#[test]
fn test_keyed_limiter_acquire_recovers_poisoned_shard() {
    // Setup a single-shard store whose lock is poisoned by a panicking holder
    let limiter = KeyedLimiter::with_shape(budget(2, 20), OnFull::AllowUntracked, 1, 10);
    limiter.acquire(1, 0);
    let result = thread::scope(|scope| {
        scope
            .spawn(|| {
                let _guard = limiter.shards[0].lock().unwrap_or_else(PoisonError::into_inner);
                panic!("poison the shard");
            })
            .join()
    });
    assert!(result.is_err());
    assert!(limiter.shards[0].is_poisoned());

    // Check the store keeps working on the existing state
    assert_eq!(limiter.acquire(1, 0), Decision::Allowed { used_pct: 100 });
    assert!(matches!(limiter.acquire(1, 0), Decision::Denied { .. }));
}

#[test]
fn test_keyed_limiter_acquire_refills_one_token_per_interval_and_fully_after_period() {
    // Setup an exhausted key with a ten-second interval
    let limiter = KeyedLimiter::new(budget(3, 30), OnFull::AllowUntracked);
    let now_ns = 100 * SEC;
    for _ in 0..3 {
        limiter.acquire(1, now_ns);
    }

    // Check one token returns after each interval
    assert!(matches!(
        limiter.acquire(1, now_ns + 10 * SEC - 1),
        Decision::Denied { .. }
    ));
    assert_eq!(
        limiter.acquire(1, now_ns + 10 * SEC),
        Decision::Allowed { used_pct: 100 }
    );
    assert!(matches!(
        limiter.acquire(1, now_ns + 10 * SEC),
        Decision::Denied { .. }
    ));

    // Check the whole burst is available one period after the last request
    let later_ns = now_ns + 40 * SEC;
    let decisions: Vec<_> = (0..4).map(|_| limiter.acquire(1, later_ns)).collect();
    assert_eq!(
        decisions,
        vec![
            Decision::Allowed { used_pct: 33 },
            Decision::Allowed { used_pct: 66 },
            Decision::Allowed { used_pct: 100 },
            Decision::Denied {
                retry_after: Duration::from_secs(10)
            },
        ]
    );
}

#[test]
fn test_keyed_limiter_acquire_saturates_at_time_bounds() {
    // Setup a store and keys used at the start and end of the representable time
    let limiter = KeyedLimiter::new(budget(1, 10), OnFull::AllowUntracked);

    // Check the process epoch behaves like any other time
    assert_eq!(limiter.acquire(1, 0), Decision::Allowed { used_pct: 100 });
    assert_eq!(
        limiter.acquire(1, 0),
        Decision::Denied {
            retry_after: Duration::from_secs(10)
        }
    );

    // Check arithmetic near the largest time saturates instead of overflowing
    assert_eq!(
        limiter.acquire(2, u64::MAX - SEC),
        Decision::Allowed { used_pct: 10 }
    );
    assert_eq!(
        limiter.acquire(2, u64::MAX),
        Decision::Allowed { used_pct: 0 }
    );
    limiter.refund(&2);
    assert_eq!(stored_ns(&limiter, 2), Some(u64::MAX - 10 * SEC));
}

#[test]
fn test_keyed_limiter_acquire_untracked_policy_keeps_existing_keys_limited() {
    // Setup a full single-shard store of exhausted keys
    let limiter = KeyedLimiter::with_shape(budget(1, 10), OnFull::AllowUntracked, 1, 2);
    limiter.acquire(1, 0);
    limiter.acquire(2, 0);

    // Send requests for a new key while the shard is full of active keys
    let decisions: Vec<_> = (0..3).map(|_| limiter.acquire(3, SEC)).collect();

    // Check the new key is allowed untracked and the existing keys stay limited
    assert!(decisions.iter().all(|decision| *decision == Decision::Untracked));
    assert_eq!(tracked_keys(&limiter), vec![1, 2]);
    assert!(matches!(limiter.acquire(1, SEC), Decision::Denied { .. }));
    assert!(matches!(limiter.acquire(2, SEC), Decision::Denied { .. }));
    assert_eq!(limiter.take_evictions(), 0);
}

#[test]
fn test_keyed_limiter_refund_does_not_bank_credit_beyond_burst() {
    // Setup a key with one token spent
    let limiter = KeyedLimiter::new(budget(2, 20), OnFull::AllowUntracked);
    let now_ns = 100 * SEC;
    limiter.acquire(1, now_ns);

    // Return more tokens than were spent
    for _ in 0..3 {
        limiter.refund(&1);
    }

    // Check the key gets exactly its burst, not more
    assert!(matches!(
        limiter.acquire(1, now_ns),
        Decision::Allowed { .. }
    ));
    assert!(matches!(
        limiter.acquire(1, now_ns),
        Decision::Allowed { .. }
    ));
    assert!(matches!(
        limiter.acquire(1, now_ns),
        Decision::Denied { .. }
    ));
}

#[test]
fn test_keyed_limiter_refund_missing_key_is_noop() {
    // Setup an empty store
    let limiter = KeyedLimiter::new(budget(2, 20), OnFull::AllowUntracked);

    // Refund a key that was never seen
    limiter.refund(&1);

    // Check nothing was tracked and the key still gets exactly its burst
    assert_eq!(tracked_keys(&limiter), Vec::<u32>::new());
    assert!(matches!(limiter.acquire(1, SEC), Decision::Allowed { .. }));
    assert!(matches!(limiter.acquire(1, SEC), Decision::Allowed { .. }));
    assert!(matches!(limiter.acquire(1, SEC), Decision::Denied { .. }));
}

#[test]
fn test_keyed_limiter_refund_restores_one_token() {
    // Setup an exhausted key
    let limiter = KeyedLimiter::new(budget(2, 20), OnFull::AllowUntracked);
    let now_ns = 100 * SEC;
    limiter.acquire(1, now_ns);
    limiter.acquire(1, now_ns);

    // Return one token
    limiter.refund(&1);

    // Check exactly one more request is allowed
    assert_eq!(
        limiter.acquire(1, now_ns),
        Decision::Allowed { used_pct: 100 }
    );
    assert!(matches!(
        limiter.acquire(1, now_ns),
        Decision::Denied { .. }
    ));
}

#[test]
fn test_nanos_since() {
    // Setup an epoch and labeled times with the expected nanoseconds
    let before_epoch = Instant::now();
    let epoch = before_epoch + Duration::from_secs(5);
    let cases = [
        ("time before the epoch saturates to zero", before_epoch, 0),
        ("the epoch is zero", epoch, 0),
        (
            "time after the epoch",
            epoch + Duration::from_millis(1_500),
            1_500_000_000,
        ),
    ];

    // Check each time converts as expected
    for (label, now, expected) in cases {
        assert_eq!(nanos_since(epoch, now), expected, "{label}");
    }
}

// Helpers.

/// Builds a budget with the given burst and period.
fn budget(burst: u32, period_secs: u64) -> RateLimitBudget {
    RateLimitBudget { burst, period_secs }
}

/// Returns the stored time of `key`, if tracked.
fn stored_ns(limiter: &KeyedLimiter<u32>, key: u32) -> Option<u64> {
    limiter.shard(&key).entries.get(&key).copied()
}

/// Returns every tracked key across all shards, sorted.
fn tracked_keys(limiter: &KeyedLimiter<u32>) -> Vec<u32> {
    let mut keys: Vec<_> = limiter
        .shards
        .iter()
        .flat_map(|shard| {
            shard
                .lock()
                .unwrap_or_else(PoisonError::into_inner)
                .entries
                .keys()
                .copied()
                .collect::<Vec<_>>()
        })
        .collect();
    keys.sort_unstable();
    keys
}
