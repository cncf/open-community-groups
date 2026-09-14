//! This module contains types and functionality used to track activities.
//!
//! It provides an asynchronous, batched mechanism for aggregating and
//! persisting tracked activities to the database. Tracking is deliberately
//! lossy: a request never waits for the tracker, and activities that cannot be
//! queued or aggregated within the configured bounds are dropped and counted.

use std::{
    collections::{HashMap, hash_map::Entry},
    sync::{
        Arc, LazyLock,
        atomic::{AtomicU64, Ordering},
    },
    time::Duration,
};

use anyhow::Result;
use async_trait::async_trait;
#[cfg(test)]
use mockall::automock;
use time::{
    OffsetDateTime,
    format_description::{self, FormatItem},
};
use tokio::{
    sync::mpsc::{self, error::TrySendError},
    time::{Instant, MissedTickBehavior},
};
use tokio_util::sync::CancellationToken;
use tracing::{error, warn};
use uuid::Uuid;

use crate::{db::activity_tracker::DynDBActivityTracker, services::workers::BackgroundTasks};

/// Format used to represent the date in the tracker.
static DATE_FORMAT: LazyLock<Vec<FormatItem<'static>>> = LazyLock::new(|| {
    format_description::parse_borrowed::<1>("[year]-[month]-[day]").expect("format to be valid")
});

/// Capacity of the queue between request handlers and the aggregator.
///
/// Activities are tiny, so a large queue absorbs traffic bursts and short
/// aggregator stalls at negligible memory cost.
const ACTIVITIES_QUEUE_CAPACITY: usize = 10_000;

/// Capacity of the queue between the aggregator and the flusher.
///
/// A single slot is enough: when the flusher is still busy at the next flush,
/// the aggregator keeps merging activities into its current batch instead of
/// waiting for a free slot.
const BATCHES_QUEUE_CAPACITY: usize = 1;

/// How often activities will be written to the database.
#[cfg(not(test))]
const FLUSH_FREQUENCY: Duration = Duration::from_mins(5);
#[cfg(test)]
const FLUSH_FREQUENCY: Duration = Duration::from_millis(100);

/// Maximum distinct (entity, day) keys aggregated in one batch across all activities.
const MAX_BATCH_KEYS: usize = 10_000;

/// Entity identifier tracked by the activity tracker.
type EntityId = Uuid;

/// Date string in `YYYY-MM-DD` format.
type Day = String;

/// Aggregated count for a day.
type Total = u32;

/// Trackable activities currently supported by the tracker.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[allow(clippy::enum_variant_names)]
pub(crate) enum Activity {
    /// A single community view.
    CommunityView { community_id: Uuid },
    /// A single event view.
    EventView { event_id: Uuid },
    /// A single group view.
    GroupView { group_id: Uuid },
}

/// Shared activity tracker handle.
pub(crate) type DynActivityTracker = Arc<dyn ActivityTracker + Send + Sync>;

/// Interface for queuing analytics activities.
#[async_trait]
#[cfg_attr(test, automock)]
pub(crate) trait ActivityTracker {
    /// Queues an activity for later persistence.
    ///
    /// Tracking is best-effort: the call never waits for queue capacity and
    /// never fails because the tracker is saturated or stopped. Activities
    /// that cannot be queued are dropped and counted.
    async fn track(&self, activity: Activity) -> Result<()>;
}

/// Database-backed activity tracker.
pub(crate) struct ActivityTrackerDB {
    /// Channel used to queue tracked activities.
    activities_tx: mpsc::Sender<Activity>,
    /// Counters describing tracking loss, shared with the aggregator.
    stats: Arc<ActivityTrackerStats>,
}

impl ActivityTrackerDB {
    /// Create a new `ActivityTrackerDB` instance.
    pub(crate) fn new(db: DynDBActivityTracker, background_tasks: &BackgroundTasks) -> Self {
        // Setup channels and shared loss counters
        let (activities_tx, activities_rx) = mpsc::channel(ACTIVITIES_QUEUE_CAPACITY);
        let (batches_tx, batches_rx) = mpsc::channel(BATCHES_QUEUE_CAPACITY);
        let stats = Arc::new(ActivityTrackerStats::default());

        // Setup and run the worker to aggregate tracked activities
        let aggregator = Aggregator {
            batches_tx,
            cancellation_token: background_tasks.cancellation_token(),
            stats: stats.clone(),
        };
        background_tasks.spawn("activity-aggregator", async move {
            aggregator.run(activities_rx).await;
        });

        // Setup and run the worker to flush activity batches
        let flusher = Flusher { db };
        background_tasks.spawn("activity-flusher", async move {
            flusher.run(batches_rx).await;
        });

        Self {
            activities_tx,
            stats,
        }
    }
}

#[async_trait]
impl ActivityTracker for ActivityTrackerDB {
    /// [`ActivityTracker::track`].
    async fn track(&self, activity: Activity) -> Result<()> {
        // Drop the activity instead of waiting when the queue is full or closed
        if let Err(TrySendError::Full(_) | TrySendError::Closed(_)) =
            self.activities_tx.try_send(activity)
        {
            self.stats.record_dropped();
        }

        Ok(())
    }
}

/// Counters describing best-effort activity tracking loss.
#[derive(Debug, Default)]
struct ActivityTrackerStats {
    /// Activities dropped because the queue was saturated or a batch reached its key cap.
    dropped_events: AtomicU64,
}

impl ActivityTrackerStats {
    /// Returns how many activities have been dropped since the process started.
    fn dropped_events(&self) -> u64 {
        self.dropped_events.load(Ordering::Relaxed)
    }

    /// Records one dropped activity.
    fn record_dropped(&self) {
        self.dropped_events.fetch_add(1, Ordering::Relaxed);
    }
}

/// Worker responsible for aggregating queued activities into batches.
struct Aggregator {
    /// Channel used to hand aggregated batches to the flusher.
    batches_tx: mpsc::Sender<Batches>,
    /// Token used to signal worker shutdown.
    cancellation_token: CancellationToken,
    /// Counters describing tracking loss, shared with the tracker handle.
    stats: Arc<ActivityTrackerStats>,
}

impl Aggregator {
    /// Main worker loop: aggregates tracked activities until cancelled.
    async fn run(&self, mut activities_rx: mpsc::Receiver<Activity>) {
        let first_flush = Instant::now() + FLUSH_FREQUENCY;
        let mut flush_interval = tokio::time::interval_at(first_flush, FLUSH_FREQUENCY);
        flush_interval.set_missed_tick_behavior(MissedTickBehavior::Skip);

        let mut batches = Batches::new();
        let mut reported_dropped_events = 0;
        loop {
            tokio::select! {
                biased;

                // Hand the current batch to the flusher on every interval tick
                _ = flush_interval.tick() => {
                    if !batches.is_empty() {
                        batches = self.hand_over_batches(batches);
                    }
                    reported_dropped_events = self.report_dropped_events(reported_dropped_events);
                }

                // Aggregate the next queued activity under the current day
                Some(activity) = activities_rx.recv() => {
                    if !batches.aggregate_activity(activity) {
                        self.stats.record_dropped();
                    }
                }

                // Flush any pending activity before stopping the worker
                () = self.cancellation_token.cancelled() => {
                    self.drain_queued_activities(&mut batches, &mut activities_rx);

                    if !batches.is_empty() {
                        _ = self.batches_tx.send(batches).await;
                    }
                    self.report_dropped_events(reported_dropped_events);
                    break;
                }
            }
        }
    }

    /// Drains queued activities into the batches, counting the ones the cap rejects.
    fn drain_queued_activities(
        &self,
        batches: &mut Batches,
        activities_rx: &mut mpsc::Receiver<Activity>,
    ) {
        while let Ok(activity) = activities_rx.try_recv() {
            if !batches.aggregate_activity(activity) {
                self.stats.record_dropped();
            }
        }
    }

    /// Hands the batch to the flusher without waiting for a free slot.
    ///
    /// Returns the batch to keep aggregating into: an empty one after a
    /// successful hand-over, or the same batch when the flusher is still busy
    /// or gone, so pending counters keep merging until the next flush.
    fn hand_over_batches(&self, batches: Batches) -> Batches {
        match self.batches_tx.try_send(batches) {
            Ok(()) => Batches::new(),
            Err(TrySendError::Full(batches) | TrySendError::Closed(batches)) => {
                warn!(
                    pending_keys = batches.total_keys,
                    "flusher unavailable, keeping batch until the next flush"
                );
                batches
            }
        }
    }

    /// Logs the activities dropped since the last report and returns the new total.
    fn report_dropped_events(&self, reported_dropped_events: u64) -> u64 {
        let dropped_events = self.stats.dropped_events();
        if dropped_events > reported_dropped_events {
            warn!(
                dropped_events = dropped_events - reported_dropped_events,
                total_dropped_events = dropped_events,
                "activity events dropped since the last flush"
            );
        }
        dropped_events
    }
}

/// Worker responsible for flushing batches into the database.
struct Flusher {
    /// Database handle used for activity tracker writes.
    db: DynDBActivityTracker,
}

impl Flusher {
    /// Main worker loop: flushes aggregated batches until the channel closes.
    async fn run(&self, mut batches_rx: mpsc::Receiver<Batches>) {
        while let Some(batches) = batches_rx.recv().await {
            // Process community views
            if !batches.community_views.is_empty() {
                let data = prepare_batch_data(&batches.community_views);
                if let Err(err) = self.db.update_community_views(data).await {
                    error!(?err, "error writing community views to database");
                }
            }

            // Process event views
            if !batches.event_views.is_empty() {
                let data = prepare_batch_data(&batches.event_views);
                if let Err(err) = self.db.update_event_views(data).await {
                    error!(?err, "error writing event views to database");
                }
            }

            // Process group views
            if !batches.group_views.is_empty() {
                let data = prepare_batch_data(&batches.group_views);
                if let Err(err) = self.db.update_group_views(data).await {
                    error!(?err, "error writing group views to database");
                }
            }
        }
    }
}

/// Converts aggregated counters into sorted database-ready rows.
fn prepare_batch_data(data: &HashMap<(EntityId, Day), Total>) -> Vec<(EntityId, Day, Total)> {
    let mut db_ready_data: Vec<(EntityId, Day, Total)> = data
        .iter()
        .map(|((entity_id, day), total)| (*entity_id, day.clone(), *total))
        .collect();
    db_ready_data.sort();
    db_ready_data
}

/// Aggregated in-memory batches.
#[derive(Debug, Default)]
struct Batches {
    /// Aggregated community view counts.
    community_views: HashMap<(EntityId, Day), Total>,
    /// Aggregated event view counts.
    event_views: HashMap<(EntityId, Day), Total>,
    /// Aggregated group view counts.
    group_views: HashMap<(EntityId, Day), Total>,
    /// Distinct keys held across all counters, bounded by [`MAX_BATCH_KEYS`].
    total_keys: usize,
}

impl Batches {
    /// Creates a new empty batches container.
    fn new() -> Self {
        Self::default()
    }

    /// Aggregates a single activity under the current day.
    ///
    /// Returns `false` when the activity introduces a new key while the batch
    /// already holds [`MAX_BATCH_KEYS`] distinct keys; the activity is dropped.
    fn aggregate_activity(&mut self, activity: Activity) -> bool {
        let day = OffsetDateTime::now_utc()
            .format(&DATE_FORMAT)
            .expect("format to succeed");

        // Select the counters and key for the activity
        let (counters, key) = match activity {
            Activity::CommunityView { community_id } => {
                (&mut self.community_views, (community_id, day))
            }
            Activity::EventView { event_id } => (&mut self.event_views, (event_id, day)),
            Activity::GroupView { group_id } => (&mut self.group_views, (group_id, day)),
        };

        // Reject a new key once the batch reached its distinct-key cap
        if !counters.contains_key(&key) && self.total_keys >= MAX_BATCH_KEYS {
            return false;
        }

        // Count the activity, tracking the new key when it is one
        match counters.entry(key) {
            Entry::Occupied(mut entry) => *entry.get_mut() += 1,
            Entry::Vacant(entry) => {
                entry.insert(1);
                self.total_keys += 1;
            }
        }

        true
    }

    /// Returns whether there is no pending data.
    fn is_empty(&self) -> bool {
        self.total_keys == 0
    }
}

#[cfg(test)]
mod tests {
    //! Tests for the activity tracking module.
    //!
    //! These tests verify that activities are flushed both periodically and on
    //! shutdown, and that no flush occurs if no activities are tracked.

    use anyhow::anyhow;
    use mockall::predicate::eq;
    use tokio::time::{sleep, timeout};

    use crate::db::activity_tracker::MockDBActivityTracker;

    use super::*;

    /// Static entity IDs used for testing.
    static COMMUNITY1_ID: LazyLock<Uuid> =
        LazyLock::new(|| Uuid::parse_str("00000000-0000-0000-0000-000000000201").unwrap());
    static COMMUNITY2_ID: LazyLock<Uuid> =
        LazyLock::new(|| Uuid::parse_str("00000000-0000-0000-0000-000000000202").unwrap());
    static EVENT1_ID: LazyLock<Uuid> =
        LazyLock::new(|| Uuid::parse_str("00000000-0000-0000-0000-000000000001").unwrap());
    static EVENT2_ID: LazyLock<Uuid> =
        LazyLock::new(|| Uuid::parse_str("00000000-0000-0000-0000-000000000002").unwrap());
    static GROUP1_ID: LazyLock<Uuid> =
        LazyLock::new(|| Uuid::parse_str("00000000-0000-0000-0000-000000000101").unwrap());
    static GROUP2_ID: LazyLock<Uuid> =
        LazyLock::new(|| Uuid::parse_str("00000000-0000-0000-0000-000000000102").unwrap());

    /// Test that activities are flushed when the tracker is stopped.
    #[tokio::test]
    async fn test_flushes_activities_on_stop() {
        // Setup mock database
        let day = OffsetDateTime::now_utc().format(&DATE_FORMAT).unwrap();
        let mut mock_db = MockDBActivityTracker::new();
        mock_db
            .expect_update_community_views()
            .with(eq(vec![
                (*COMMUNITY1_ID, day.clone(), 2),
                (*COMMUNITY2_ID, day.clone(), 1),
            ]))
            .times(1)
            .returning(|_| Ok(()));
        mock_db
            .expect_update_event_views()
            .with(eq(vec![
                (*EVENT1_ID, day.clone(), 2),
                (*EVENT2_ID, day.clone(), 1),
            ]))
            .times(1)
            .returning(|_| Ok(()));
        mock_db
            .expect_update_group_views()
            .with(eq(vec![(*GROUP1_ID, day.clone(), 2), (*GROUP2_ID, day, 1)]))
            .times(1)
            .returning(|_| Ok(()));
        let mock_db = Arc::new(mock_db);

        // Setup tracker and track some activities
        let background_tasks = BackgroundTasks::new(Duration::from_secs(5));
        let tracker = ActivityTrackerDB::new(mock_db, &background_tasks);
        tracker
            .track(Activity::CommunityView {
                community_id: *COMMUNITY1_ID,
            })
            .await
            .unwrap();
        tracker
            .track(Activity::CommunityView {
                community_id: *COMMUNITY1_ID,
            })
            .await
            .unwrap();
        tracker
            .track(Activity::CommunityView {
                community_id: *COMMUNITY2_ID,
            })
            .await
            .unwrap();
        tracker
            .track(Activity::EventView {
                event_id: *EVENT1_ID,
            })
            .await
            .unwrap();
        tracker
            .track(Activity::EventView {
                event_id: *EVENT1_ID,
            })
            .await
            .unwrap();
        tracker
            .track(Activity::EventView {
                event_id: *EVENT2_ID,
            })
            .await
            .unwrap();
        tracker
            .track(Activity::GroupView {
                group_id: *GROUP1_ID,
            })
            .await
            .unwrap();
        tracker
            .track(Activity::GroupView {
                group_id: *GROUP1_ID,
            })
            .await
            .unwrap();
        tracker
            .track(Activity::GroupView {
                group_id: *GROUP2_ID,
            })
            .await
            .unwrap();

        // Stop the tracker and wait for the workers to complete
        background_tasks.shutdown().await;
    }

    /// Test that activities are flushed periodically.
    #[tokio::test]
    async fn test_flushes_activities_periodically() {
        // Setup mock database
        let day = OffsetDateTime::now_utc().format(&DATE_FORMAT).unwrap();
        let mut mock_db = MockDBActivityTracker::new();
        mock_db
            .expect_update_community_views()
            .with(eq(vec![(*COMMUNITY1_ID, day.clone(), 1)]))
            .times(1)
            .returning(|_| Ok(()));
        mock_db
            .expect_update_event_views()
            .with(eq(vec![(*EVENT1_ID, day.clone(), 1)]))
            .times(1)
            .returning(|_| Ok(()));
        mock_db
            .expect_update_group_views()
            .with(eq(vec![(*GROUP1_ID, day, 1)]))
            .times(1)
            .returning(|_| Ok(()));
        let mock_db = Arc::new(mock_db);

        // Setup tracker and track some activities
        let background_tasks = BackgroundTasks::new(Duration::from_secs(5));
        let tracker = ActivityTrackerDB::new(mock_db, &background_tasks);
        tracker
            .track(Activity::CommunityView {
                community_id: *COMMUNITY1_ID,
            })
            .await
            .unwrap();
        tracker
            .track(Activity::EventView {
                event_id: *EVENT1_ID,
            })
            .await
            .unwrap();
        tracker
            .track(Activity::GroupView {
                group_id: *GROUP1_ID,
            })
            .await
            .unwrap();

        // Wait for the periodic flush to complete
        sleep(FLUSH_FREQUENCY * 2).await;

        // Stop the tracker and wait for the workers to complete
        background_tasks.shutdown().await;
    }

    /// Test that nothing is flushed if no activities are tracked.
    #[tokio::test]
    async fn test_skips_flush_when_no_activities_are_tracked() {
        // Setup tracker with no activities tracked
        let mock_db = Arc::new(MockDBActivityTracker::new());
        let background_tasks = BackgroundTasks::new(Duration::from_secs(5));
        let _tracker = ActivityTrackerDB::new(mock_db, &background_tasks);

        // Wait long enough for a periodic flush attempt
        sleep(FLUSH_FREQUENCY * 2).await;

        // Stop the tracker and wait for the workers to complete
        background_tasks.shutdown().await;
    }

    /// Test that queued activities are drained into the final shutdown batch.
    #[tokio::test]
    async fn test_drains_queued_activities_on_stop() {
        // Setup channels and cancellation state
        let day = OffsetDateTime::now_utc().format(&DATE_FORMAT).unwrap();
        let (activities_tx, activities_rx) = mpsc::channel(10);
        let (batches_tx, mut batches_rx) = mpsc::channel(1);
        let cancellation_token = CancellationToken::new();

        // Queue activities before the aggregator starts listening
        activities_tx
            .send(Activity::CommunityView {
                community_id: *COMMUNITY1_ID,
            })
            .await
            .unwrap();
        activities_tx
            .send(Activity::EventView {
                event_id: *EVENT1_ID,
            })
            .await
            .unwrap();
        activities_tx
            .send(Activity::GroupView {
                group_id: *GROUP1_ID,
            })
            .await
            .unwrap();

        // Start the aggregator and stop it immediately to force a drain
        let aggregator = Aggregator {
            batches_tx,
            cancellation_token: cancellation_token.clone(),
            stats: Arc::new(ActivityTrackerStats::default()),
        };
        let aggregator_handle = tokio::spawn(async move {
            aggregator.run(activities_rx).await;
        });
        cancellation_token.cancel();
        aggregator_handle.await.unwrap();

        // Verify all queued activities were included in the final batch
        let batches = batches_rx.recv().await.unwrap();
        assert_eq!(
            prepare_batch_data(&batches.community_views),
            vec![(*COMMUNITY1_ID, day.clone(), 1)]
        );
        assert_eq!(
            prepare_batch_data(&batches.event_views),
            vec![(*EVENT1_ID, day.clone(), 1)]
        );
        assert_eq!(
            prepare_batch_data(&batches.group_views),
            vec![(*GROUP1_ID, day, 1)]
        );
    }

    /// Test that a batch stops accepting new keys at the cap and counts the overflow.
    #[test]
    fn test_batches_cap_distinct_keys_and_reject_overflow() {
        // Fill the batch with the maximum number of distinct keys
        let mut batches = Batches::new();
        for _ in 0..MAX_BATCH_KEYS {
            assert!(batches.aggregate_activity(Activity::EventView {
                event_id: Uuid::new_v4(),
            }));
        }

        // Check a new key is rejected while an existing key still aggregates
        assert!(!batches.aggregate_activity(Activity::GroupView {
            group_id: *GROUP1_ID,
        }));
        let existing_event_id = *batches.event_views.keys().next().map(|(id, _)| id).unwrap();
        assert!(batches.aggregate_activity(Activity::EventView {
            event_id: existing_event_id,
        }));
        assert_eq!(batches.total_keys, MAX_BATCH_KEYS);
        assert!(batches.group_views.is_empty());
    }

    /// Test that a busy flusher does not block the aggregator and pending counters keep merging.
    #[tokio::test]
    async fn test_keeps_aggregating_when_flusher_is_busy() {
        // Setup a batches queue whose only slot is taken to simulate a busy flusher
        let day = OffsetDateTime::now_utc().format(&DATE_FORMAT).unwrap();
        let (activities_tx, activities_rx) = mpsc::channel(10);
        let (batches_tx, mut batches_rx) = mpsc::channel(1);
        batches_tx.send(Batches::new()).await.unwrap();

        // Start the aggregator
        let cancellation_token = CancellationToken::new();
        let stats = Arc::new(ActivityTrackerStats::default());
        let aggregator = Aggregator {
            batches_tx,
            cancellation_token: cancellation_token.clone(),
            stats: stats.clone(),
        };
        let aggregator_handle = tokio::spawn(async move {
            aggregator.run(activities_rx).await;
        });

        // Track an activity and let a flush tick pass while the flusher is busy
        activities_tx
            .send(Activity::CommunityView {
                community_id: *COMMUNITY1_ID,
            })
            .await
            .unwrap();
        sleep(FLUSH_FREQUENCY * 2).await;

        // Track another activity for the same key and let it be aggregated while
        // the flusher is still busy, then free the flusher slot
        activities_tx
            .send(Activity::CommunityView {
                community_id: *COMMUNITY1_ID,
            })
            .await
            .unwrap();
        sleep(FLUSH_FREQUENCY * 2).await;
        let placeholder = batches_rx.recv().await.unwrap();
        assert!(placeholder.is_empty());

        // Check the next flush hands over a single merged batch with nothing dropped
        let batches = timeout(FLUSH_FREQUENCY * 5, batches_rx.recv())
            .await
            .unwrap()
            .unwrap();
        assert_eq!(
            prepare_batch_data(&batches.community_views),
            vec![(*COMMUNITY1_ID, day, 2)]
        );
        assert_eq!(stats.dropped_events(), 0);

        // Stop the aggregator
        cancellation_token.cancel();
        aggregator_handle.await.unwrap();
    }

    /// Test that a database failure drops the affected counters and the flusher continues.
    #[tokio::test]
    async fn test_flusher_continues_after_database_failure() {
        // Setup a database that rejects the first batch's community views only
        let day = OffsetDateTime::now_utc().format(&DATE_FORMAT).unwrap();
        let mut mock_db = MockDBActivityTracker::new();
        mock_db
            .expect_update_community_views()
            .with(eq(vec![(*COMMUNITY1_ID, day.clone(), 1)]))
            .times(1)
            .returning(|_| Err(anyhow!("database unavailable")));
        mock_db
            .expect_update_event_views()
            .with(eq(vec![(*EVENT1_ID, day.clone(), 1)]))
            .times(1)
            .returning(|_| Ok(()));
        mock_db
            .expect_update_group_views()
            .with(eq(vec![(*GROUP1_ID, day.clone(), 1)]))
            .times(1)
            .returning(|_| Ok(()));

        // Queue two batches: one that fails partially and one that follows it
        let (batches_tx, batches_rx) = mpsc::channel(2);
        let mut first = Batches::new();
        first.aggregate_activity(Activity::CommunityView {
            community_id: *COMMUNITY1_ID,
        });
        first.aggregate_activity(Activity::EventView {
            event_id: *EVENT1_ID,
        });
        let mut second = Batches::new();
        second.aggregate_activity(Activity::GroupView {
            group_id: *GROUP1_ID,
        });
        batches_tx.send(first).await.unwrap();
        batches_tx.send(second).await.unwrap();
        drop(batches_tx);

        // Run the flusher until the channel closes
        let flusher = Flusher {
            db: Arc::new(mock_db),
        };
        flusher.run(batches_rx).await;
    }

    /// Test that shutdown completes within the grace period while the flusher is congested.
    #[tokio::test(start_paused = true)]
    async fn test_shutdown_under_congestion_exits_within_grace_period() {
        // Setup a batches queue whose only slot is taken and never drained
        let (activities_tx, activities_rx) = mpsc::channel(10);
        let (batches_tx, _batches_rx) = mpsc::channel(1);
        batches_tx.send(Batches::new()).await.unwrap();

        // Start the aggregator under shutdown coordination with a five second grace period
        let background_tasks = BackgroundTasks::new(Duration::from_secs(5));
        let stats = Arc::new(ActivityTrackerStats::default());
        let aggregator = Aggregator {
            batches_tx,
            cancellation_token: background_tasks.cancellation_token(),
            stats: stats.clone(),
        };
        background_tasks.spawn("activity-aggregator", async move {
            aggregator.run(activities_rx).await;
        });

        // Queue an activity so the shutdown flush has a batch to hand over
        activities_tx
            .send(Activity::CommunityView {
                community_id: *COMMUNITY1_ID,
            })
            .await
            .unwrap();

        // Stop the tracker and check shutdown returns at the grace period boundary
        let started_at = Instant::now();
        background_tasks.shutdown().await;
        assert_eq!(started_at.elapsed(), Duration::from_secs(5));
        assert_eq!(stats.dropped_events(), 0);
    }

    /// Test that tracking never waits on a full queue and counts the dropped activity.
    #[tokio::test]
    async fn test_track_drops_activity_when_queue_is_full() {
        // Setup a tracker whose single-slot queue has no consumer
        let (activities_tx, _activities_rx) = mpsc::channel(1);
        let tracker = ActivityTrackerDB {
            activities_tx,
            stats: Arc::new(ActivityTrackerStats::default()),
        };

        // Track two activities without anyone draining the queue
        let result = timeout(Duration::from_secs(1), async {
            tracker
                .track(Activity::EventView {
                    event_id: *EVENT1_ID,
                })
                .await
                .unwrap();
            tracker
                .track(Activity::EventView {
                    event_id: *EVENT2_ID,
                })
                .await
                .unwrap();
        })
        .await;

        // Check the request path returned and the overflow was counted
        assert!(result.is_ok());
        assert_eq!(tracker.stats.dropped_events(), 1);
    }
}
