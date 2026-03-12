//! This module contains types and functionality used to track activities.
//!
//! It provides an asynchronous, batched mechanism for aggregating and
//! persisting tracked activities to the database.

use std::{collections::HashMap, sync::Arc, sync::LazyLock, time::Duration};

use anyhow::Result;
use async_trait::async_trait;
#[cfg(test)]
use mockall::automock;
use time::{
    OffsetDateTime,
    format_description::{self, FormatItem},
};
use tokio::{
    sync::mpsc,
    time::{Instant, MissedTickBehavior},
};
use tokio_util::{sync::CancellationToken, task::TaskTracker};
use tracing::error;
use uuid::Uuid;

use crate::db::activity_tracker::DynDBActivityTracker;

/// Format used to represent the date in the tracker.
static DATE_FORMAT: LazyLock<Vec<FormatItem<'static>>> =
    LazyLock::new(|| format_description::parse("[year]-[month]-[day]").expect("format to be valid"));

/// How often activities will be written to the database.
#[cfg(not(test))]
const FLUSH_FREQUENCY: Duration = Duration::from_secs(300);
#[cfg(test)]
const FLUSH_FREQUENCY: Duration = Duration::from_millis(100);

/// Shared activity tracker handle.
pub(crate) type DynActivityTracker = Arc<dyn ActivityTracker + Send + Sync>;

/// Entity identifier tracked by the activity tracker.
type EntityId = Uuid;

/// Date string in `YYYY-MM-DD` format.
type Day = String;

/// Aggregated count for a day.
type Total = u32;

/// Aggregated in-memory batches.
#[derive(Debug, Clone, Default)]
struct Batches {
    community_views: HashMap<(EntityId, Day), Total>,
    event_views: HashMap<(EntityId, Day), Total>,
    group_views: HashMap<(EntityId, Day), Total>,
}

impl Batches {
    /// Creates a new empty batches container.
    fn new() -> Self {
        Self::default()
    }

    /// Returns whether there is no pending data.
    fn is_empty(&self) -> bool {
        self.community_views.is_empty() && self.event_views.is_empty() && self.group_views.is_empty()
    }

    /// Clears all pending data.
    fn clear(&mut self) {
        self.community_views.clear();
        self.event_views.clear();
        self.group_views.clear();
    }
}

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

/// Interface for queuing analytics activities.
#[async_trait]
#[cfg_attr(test, automock)]
pub(crate) trait ActivityTracker {
    /// Enqueues an activity for later persistence.
    async fn track(&self, activity: Activity) -> Result<()>;
}

/// Database-backed activity tracker.
pub(crate) struct ActivityTrackerDB {
    activities_tx: mpsc::Sender<Activity>,
}

impl ActivityTrackerDB {
    /// Creates a new tracker and starts background workers.
    pub(crate) fn new(
        db: DynDBActivityTracker,
        task_tracker: &TaskTracker,
        cancellation_token: &CancellationToken,
    ) -> Self {
        // Setup channels.
        let (activities_tx, activities_rx) = mpsc::channel(100);
        let (batches_tx, batches_rx) = mpsc::channel(5);

        // Setup workers.
        task_tracker.spawn(aggregator(activities_rx, batches_tx, cancellation_token.clone()));
        task_tracker.spawn(flusher(db, batches_rx));

        Self { activities_tx }
    }
}

#[async_trait]
impl ActivityTracker for ActivityTrackerDB {
    async fn track(&self, activity: Activity) -> Result<()> {
        self.activities_tx.send(activity).await.map_err(Into::into)
    }
}

/// Aggregates incoming activities into in-memory daily batches.
async fn aggregator(
    mut activities_rx: mpsc::Receiver<Activity>,
    batches_tx: mpsc::Sender<Batches>,
    cancellation_token: CancellationToken,
) {
    let first_flush = Instant::now() + FLUSH_FREQUENCY;
    let mut flush_interval = tokio::time::interval_at(first_flush, FLUSH_FREQUENCY);
    flush_interval.set_missed_tick_behavior(MissedTickBehavior::Skip);

    let mut batches = Batches::new();
    loop {
        tokio::select! {
            biased;

            // Send the current batch to the flusher on every interval tick.
            _ = flush_interval.tick() => {
                if !batches.is_empty() && batches_tx.send(batches.clone()).await.is_ok() {
                    batches.clear();
                }
            }

            // Pick the next queued activity and aggregate it under the current day.
            Some(activity) = activities_rx.recv() => {
                aggregate_activity(&mut batches, activity);
            }

            // Flush any pending activity before stopping the worker.
            () = cancellation_token.cancelled() => {
                drain_queued_activities(&mut activities_rx, &mut batches);

                if !batches.is_empty() {
                    _ = batches_tx.send(batches).await;
                }
                break;
            }
        }
    }
}

/// Aggregates a single activity under the current day.
fn aggregate_activity(batches: &mut Batches, activity: Activity) {
    let day = OffsetDateTime::now_utc()
        .format(&DATE_FORMAT)
        .expect("format to succeed");

    match activity {
        Activity::CommunityView { community_id } => {
            *batches.community_views.entry((community_id, day)).or_default() += 1;
        }
        Activity::EventView { event_id } => {
            *batches.event_views.entry((event_id, day)).or_default() += 1;
        }
        Activity::GroupView { group_id } => {
            *batches.group_views.entry((group_id, day)).or_default() += 1;
        }
    }
}

/// Drains queued activities into the in-memory batches.
fn drain_queued_activities(activities_rx: &mut mpsc::Receiver<Activity>, batches: &mut Batches) {
    while let Ok(activity) = activities_rx.try_recv() {
        aggregate_activity(batches, activity);
    }
}

/// Flushes aggregated batches into the database.
async fn flusher(db: DynDBActivityTracker, mut batches_rx: mpsc::Receiver<Batches>) {
    while let Some(batches) = batches_rx.recv().await {
        // Process community views.
        if !batches.community_views.is_empty() {
            let data = prepare_batch_data(&batches.community_views);
            if let Err(err) = db.update_community_views(data).await {
                error!(?err, "error writing community views to database");
            }
        }

        // Process event views.
        if !batches.event_views.is_empty() {
            let data = prepare_batch_data(&batches.event_views);
            if let Err(err) = db.update_event_views(data).await {
                error!(?err, "error writing event views to database");
            }
        }

        // Process group views.
        if !batches.group_views.is_empty() {
            let data = prepare_batch_data(&batches.group_views);
            if let Err(err) = db.update_group_views(data).await {
                error!(?err, "error writing group views to database");
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

#[cfg(test)]
mod tests {
    //! Tests for the activity tracking module.
    //!
    //! These tests verify that activities are flushed both periodically and on
    //! shutdown, and that no flush occurs if no activities are tracked.

    use mockall::predicate::eq;
    use tokio::time::sleep;

    use crate::db::mock::MockDB;

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
        let mut mock_db = MockDB::new();
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
        let task_tracker = TaskTracker::new();
        let cancellation_token = CancellationToken::new();
        let tracker = ActivityTrackerDB::new(mock_db, &task_tracker, &cancellation_token);
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
            .track(Activity::EventView { event_id: *EVENT1_ID })
            .await
            .unwrap();
        tracker
            .track(Activity::EventView { event_id: *EVENT1_ID })
            .await
            .unwrap();
        tracker
            .track(Activity::EventView { event_id: *EVENT2_ID })
            .await
            .unwrap();
        tracker
            .track(Activity::GroupView { group_id: *GROUP1_ID })
            .await
            .unwrap();
        tracker
            .track(Activity::GroupView { group_id: *GROUP1_ID })
            .await
            .unwrap();
        tracker
            .track(Activity::GroupView { group_id: *GROUP2_ID })
            .await
            .unwrap();

        // Stop the tracker and wait for the workers to complete
        task_tracker.close();
        cancellation_token.cancel();
        task_tracker.wait().await;
    }

    /// Test that activities are flushed periodically.
    #[tokio::test]
    async fn test_flushes_activities_periodically() {
        // Setup mock database
        let day = OffsetDateTime::now_utc().format(&DATE_FORMAT).unwrap();
        let mut mock_db = MockDB::new();
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
        let task_tracker = TaskTracker::new();
        let cancellation_token = CancellationToken::new();
        let tracker = ActivityTrackerDB::new(mock_db, &task_tracker, &cancellation_token);
        tracker
            .track(Activity::CommunityView {
                community_id: *COMMUNITY1_ID,
            })
            .await
            .unwrap();
        tracker
            .track(Activity::EventView { event_id: *EVENT1_ID })
            .await
            .unwrap();
        tracker
            .track(Activity::GroupView { group_id: *GROUP1_ID })
            .await
            .unwrap();

        // Wait for the periodic flush to complete
        sleep(FLUSH_FREQUENCY * 2).await;

        // Stop the tracker and wait for the workers to complete
        task_tracker.close();
        cancellation_token.cancel();
        task_tracker.wait().await;
    }

    /// Test that nothing is flushed if no activities are tracked.
    #[tokio::test]
    async fn test_skips_flush_when_no_activities_are_tracked() {
        // Setup tracker with no activities tracked
        let mock_db = Arc::new(MockDB::new());

        let task_tracker = TaskTracker::new();
        let cancellation_token = CancellationToken::new();
        let _tracker = ActivityTrackerDB::new(mock_db, &task_tracker, &cancellation_token);

        // Wait long enough for a periodic flush attempt
        sleep(FLUSH_FREQUENCY * 2).await;

        // Stop the tracker and wait for the workers to complete
        task_tracker.close();
        cancellation_token.cancel();
        task_tracker.wait().await;
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
            .send(Activity::EventView { event_id: *EVENT1_ID })
            .await
            .unwrap();
        activities_tx
            .send(Activity::GroupView { group_id: *GROUP1_ID })
            .await
            .unwrap();

        // Start the aggregator and stop it immediately to force a drain
        let aggregator_handle =
            tokio::spawn(aggregator(activities_rx, batches_tx, cancellation_token.clone()));
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
}
