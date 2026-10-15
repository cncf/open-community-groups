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
            utm: None,
        })
        .await
        .unwrap();
    tracker
        .track(Activity::EventView {
            event_id: *EVENT1_ID,
            utm: None,
        })
        .await
        .unwrap();
    tracker
        .track(Activity::EventView {
            event_id: *EVENT2_ID,
            utm: None,
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
            utm: None,
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
            utm: None,
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
        assert_eq!(
            batches.aggregate_activity(Activity::EventView {
                event_id: Uuid::new_v4(),
                utm: None,
            }),
            AggregationOutcome::Counted
        );
    }

    // Check a new key is rejected while an existing key still aggregates
    assert_eq!(
        batches.aggregate_activity(Activity::GroupView {
            group_id: *GROUP1_ID,
        }),
        AggregationOutcome::Dropped
    );
    let existing_event_id = *batches.event_views.keys().next().map(|(id, _)| id).unwrap();
    assert_eq!(
        batches.aggregate_activity(Activity::EventView {
            event_id: existing_event_id,
            utm: None,
        }),
        AggregationOutcome::Counted
    );
    assert_eq!(batches.total_keys, MAX_BATCH_KEYS);
    assert!(batches.group_views.is_empty());
}

#[test]
fn test_batches_cap_utm_keys_without_dropping_views() {
    // Fill the batch with the maximum number of distinct UTM keys
    let mut batches = Batches::new();
    for index in 0..MAX_BATCH_UTM_KEYS {
        assert_eq!(
            batches.aggregate_activity(Activity::EventView {
                event_id: *EVENT1_ID,
                utm: UtmParams::new(None, None, Some(&format!("source-{index}"))),
            }),
            AggregationOutcome::Counted
        );
    }

    // Check a new UTM key only drops the attribution while the view still counts
    assert_eq!(
        batches.aggregate_activity(Activity::EventView {
            event_id: *EVENT1_ID,
            utm: UtmParams::new(None, None, Some("overflow")),
        }),
        AggregationOutcome::AttributionDropped
    );
    assert_eq!(
        batches.event_views.get(&(*EVENT1_ID, current_day())),
        Some(&u32::try_from(MAX_BATCH_UTM_KEYS + 1).unwrap())
    );
    assert_eq!(batches.total_keys, 1);
    assert_eq!(batches.total_utm_keys, MAX_BATCH_UTM_KEYS);

    // Check an existing UTM key still aggregates at the cap
    assert_eq!(
        batches.aggregate_activity(Activity::EventView {
            event_id: *EVENT1_ID,
            utm: UtmParams::new(None, None, Some("source-0")),
        }),
        AggregationOutcome::Counted
    );
    assert_eq!(batches.total_utm_keys, MAX_BATCH_UTM_KEYS);
}

#[test]
fn test_batches_count_utm_attribution_alongside_views() {
    // Aggregate attributed and unattributed views of the same event
    let day = current_day();
    let newsletter = UtmParams::new(Some("launch"), Some("email"), Some("newsletter"));
    let social = UtmParams::new(None, None, Some("mastodon"));
    let mut batches = Batches::new();
    for utm in [newsletter.clone(), newsletter, social, None] {
        assert_eq!(
            batches.aggregate_activity(Activity::EventView {
                event_id: *EVENT1_ID,
                utm,
            }),
            AggregationOutcome::Counted
        );
    }

    // Check every view counts once and attributed views count per UTM parameters
    assert_eq!(
        prepare_batch_data(&batches.event_views),
        vec![(*EVENT1_ID, day.clone(), 4)]
    );
    assert_eq!(
        prepare_utm_batch_data(&batches.event_views_utm),
        vec![
            (
                *EVENT1_ID,
                day.clone(),
                String::new(),
                String::new(),
                "mastodon".to_string(),
                1
            ),
            (
                *EVENT1_ID,
                day,
                "launch".to_string(),
                "email".to_string(),
                "newsletter".to_string(),
                2
            ),
        ]
    );
    assert_eq!(batches.total_keys, 1);
    assert_eq!(batches.total_utm_keys, 2);
}

#[test]
fn test_batches_skip_utm_attribution_of_dropped_views() {
    // Fill the batch with the maximum number of distinct view keys
    let mut batches = Batches::new();
    for _ in 0..MAX_BATCH_KEYS {
        assert_eq!(
            batches.aggregate_activity(Activity::GroupView {
                group_id: Uuid::new_v4(),
            }),
            AggregationOutcome::Counted
        );
    }

    // Check a dropped view is not attributed either
    assert_eq!(
        batches.aggregate_activity(Activity::EventView {
            event_id: *EVENT1_ID,
            utm: UtmParams::new(None, None, Some("newsletter")),
        }),
        AggregationOutcome::Dropped
    );
    assert!(batches.event_views.is_empty());
    assert!(batches.event_views_utm.is_empty());
    assert_eq!(batches.total_utm_keys, 0);
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
        utm: None,
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

#[tokio::test]
async fn test_flusher_writes_event_views_utm() {
    // Setup a database expecting the view and UTM counters of one batch
    let day = current_day();
    let mut mock_db = MockDBActivityTracker::new();
    mock_db
        .expect_update_event_views()
        .with(eq(vec![(*EVENT1_ID, day.clone(), 2)]))
        .times(1)
        .returning(|_| Ok(()));
    mock_db
        .expect_update_event_views_utm()
        .with(eq(vec![(
            *EVENT1_ID,
            day,
            String::new(),
            "email".to_string(),
            "newsletter".to_string(),
            1,
        )]))
        .times(1)
        .returning(|_| Ok(()));

    // Queue a batch with one attributed and one unattributed view
    let (batches_tx, batches_rx) = mpsc::channel(1);
    let mut batches = Batches::new();
    batches.aggregate_activity(Activity::EventView {
        event_id: *EVENT1_ID,
        utm: UtmParams::new(None, Some("email"), Some("newsletter")),
    });
    batches.aggregate_activity(Activity::EventView {
        event_id: *EVENT1_ID,
        utm: None,
    });
    batches_tx.send(batches).await.unwrap();
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

#[test]
fn test_stats_record_aggregation_counts_losses_separately() {
    // Record one aggregation outcome of each kind
    let stats = ActivityTrackerStats::default();
    for outcome in [
        AggregationOutcome::AttributionDropped,
        AggregationOutcome::Counted,
        AggregationOutcome::Dropped,
    ] {
        stats.record_aggregation(outcome);
    }

    // Check dropped activities and dropped attributions are counted apart
    assert_eq!(stats.dropped_events(), 1);
    assert_eq!(stats.dropped_utm_attributions(), 1);
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
                utm: None,
            })
            .await
            .unwrap();
        tracker
            .track(Activity::EventView {
                event_id: *EVENT2_ID,
                utm: None,
            })
            .await
            .unwrap();
    })
    .await;

    // Check the request path returned and the overflow was counted
    assert!(result.is_ok());
    assert_eq!(tracker.stats.dropped_events(), 1);
}

#[test]
fn test_prepare_utm_batch_data_encodes_missing_values_as_empty_strings() {
    // Aggregate a view attributed only to a campaign
    let mut batches = Batches::new();
    batches.aggregate_activity(Activity::EventView {
        event_id: *EVENT1_ID,
        utm: UtmParams::new(Some("spring-launch"), None, None),
    });

    // Check the missing medium and source are encoded as empty strings
    assert_eq!(
        prepare_utm_batch_data(&batches.event_views_utm),
        vec![(
            *EVENT1_ID,
            current_day(),
            "spring-launch".to_string(),
            String::new(),
            String::new(),
            1
        )]
    );
}

// Helpers.

/// Returns the current day in the tracker date format.
fn current_day() -> Day {
    OffsetDateTime::now_utc().format(&DATE_FORMAT).unwrap()
}
