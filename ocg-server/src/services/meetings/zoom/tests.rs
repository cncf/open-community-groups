use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::Duration,
};

use axum::{
    Json, Router,
    extract::{Path, Query},
    http::StatusCode,
    routing::{get, post},
};
use serde_json::{Value, json};
use uuid::Uuid;

use crate::{
    config::{HttpClientConfig, MeetingsZoomConfig},
    services::meetings::{MeetingEndResult, MeetingProviderError, MeetingsProvider},
    types::meetings::Meeting,
};

use super::ZoomMeetingsProvider;

/// Host reserved for the meeting under test.
const ASSIGNED_HOST: &str = "assigned@example.com";

/// Other host in the pool, listed before the assigned one.
const OTHER_HOST: &str = "other@example.com";

#[tokio::test]
async fn test_create_meeting_adopts_meeting_found_on_another_host() {
    // Serve a pool where another host owns the meeting from an interrupted creation
    let event_id = Uuid::new_v4();
    let calls = Arc::new(Mutex::new(Vec::new()));
    let listings = HashMap::from([
        (
            OTHER_HOST.to_string(),
            vec![json!({
                "meetings": [
                    {"id": 1, "agenda": "ocg:event:other"},
                    {"id": 555, "agenda": format!("ocg:event:{event_id}")},
                ],
                "next_page_token": "",
            })],
        ),
        (ASSIGNED_HOST.to_string(), vec![json!({"meetings": []})]),
    ]);
    let api = spawn_zoom_api(fake_zoom_api(&calls, listings, None)).await;
    let provider = sample_zoom_provider(&api);

    // Retry creating the meeting after a prior create attempt
    let provider_meeting = provider
        .create_meeting(&sample_retry_meeting(event_id, None))
        .await
        .expect("meeting to be adopted");

    // Check the existing meeting was updated and re-read instead of created again
    let calls = calls.lock().expect("calls lock to be available").clone();
    assert_eq!(
        calls,
        vec![
            format!("GET /users/{OTHER_HOST}/meetings page_size=300 type=scheduled"),
            format!("PATCH /meetings/555 agenda=ocg:event:{event_id} topic=Test Meeting"),
            "GET /meetings/555".to_string(),
        ]
    );
    assert_eq!(provider_meeting.id, "555");
    assert_eq!(provider_meeting.join_url, "https://zoom.us/j/555");
    assert_eq!(provider_meeting.host_user_id.as_deref(), Some(OTHER_HOST));
    assert_eq!(
        provider_meeting.password.as_deref(),
        Some("existing-secret")
    );
}

#[tokio::test]
async fn test_create_meeting_creates_when_no_host_has_the_reference() {
    // Serve a pool where no host owns a meeting stamped with the reference
    let event_id = Uuid::new_v4();
    let calls = Arc::new(Mutex::new(Vec::new()));
    let listings = HashMap::from([
        (
            OTHER_HOST.to_string(),
            vec![json!({"meetings": [{"id": 1, "agenda": "ocg:event:other"}]})],
        ),
        (
            ASSIGNED_HOST.to_string(),
            vec![json!({"meetings": [{"id": 2, "agenda": "Weekly sync"}]})],
        ),
    ]);
    let api = spawn_zoom_api(fake_zoom_api(&calls, listings, None)).await;
    let provider = sample_zoom_provider(&api);

    // Retry creating the meeting after a prior create attempt
    let provider_meeting = provider
        .create_meeting(&sample_retry_meeting(event_id, None))
        .await
        .expect("meeting to be created");

    // Check both hosts were searched before creating on the assigned host
    let calls = calls.lock().expect("calls lock to be available").clone();
    assert_eq!(
        calls,
        vec![
            format!("GET /users/{OTHER_HOST}/meetings page_size=300 type=scheduled"),
            format!("GET /users/{ASSIGNED_HOST}/meetings page_size=300 type=scheduled"),
            format!("POST /users/{ASSIGNED_HOST}/meetings agenda=ocg:event:{event_id}"),
        ]
    );
    assert_eq!(provider_meeting.id, "9001");
    assert_eq!(provider_meeting.join_url, "https://zoom.us/j/9001");
    assert_eq!(
        provider_meeting.host_user_id.as_deref(),
        Some(ASSIGNED_HOST)
    );
    assert_eq!(provider_meeting.password.as_deref(), Some("created-secret"));
}

#[tokio::test]
async fn test_create_meeting_fails_instead_of_creating_when_a_listing_fails() {
    // Serve a pool where one host cannot be listed
    let event_id = Uuid::new_v4();
    let calls = Arc::new(Mutex::new(Vec::new()));
    let listings = HashMap::from([(ASSIGNED_HOST.to_string(), vec![json!({"meetings": []})])]);
    let api = spawn_zoom_api(fake_zoom_api(
        &calls,
        listings,
        Some((OTHER_HOST.to_string(), StatusCode::NOT_FOUND)),
    ))
    .await;
    let provider = sample_zoom_provider(&api);

    // Retry creating the meeting after a prior create attempt
    let err = provider
        .create_meeting(&sample_retry_meeting(event_id, None))
        .await
        .expect_err("listing failure to fail the creation");

    // Check the failure surfaced before any meeting was created
    assert!(matches!(err, MeetingProviderError::Client(_)), "{err}");
    let calls = calls.lock().expect("calls lock to be available").clone();
    assert_eq!(
        calls,
        vec![format!(
            "GET /users/{OTHER_HOST}/meetings page_size=300 type=scheduled"
        )]
    );
}

#[tokio::test]
async fn test_create_meeting_falls_back_to_remaining_hosts_after_last_host_miss() {
    // Serve a pool where the meeting is on OTHER_HOST while last_provider_host_user is ASSIGNED_HOST
    let event_id = Uuid::new_v4();
    let calls = Arc::new(Mutex::new(Vec::new()));
    let listings = HashMap::from([
        (
            OTHER_HOST.to_string(),
            vec![json!({"meetings": [{"id": 888, "agenda": format!("ocg:event:{event_id}")}]})],
        ),
        (ASSIGNED_HOST.to_string(), vec![json!({"meetings": []})]),
    ]);
    let api = spawn_zoom_api(fake_zoom_api(&calls, listings, None)).await;
    let provider = sample_zoom_provider(&api);

    // Retry creating the meeting with a sticky host hint pointing to the second pool host
    let provider_meeting = provider
        .create_meeting(&sample_retry_meeting(event_id, Some(ASSIGNED_HOST)))
        .await
        .expect("meeting to be adopted from fallback host");

    // Check ASSIGNED_HOST was scanned first, then OTHER_HOST was scanned and adopted
    let calls = calls.lock().expect("calls lock to be available").clone();
    assert_eq!(
        calls,
        vec![
            format!("GET /users/{ASSIGNED_HOST}/meetings page_size=300 type=scheduled"),
            format!("GET /users/{OTHER_HOST}/meetings page_size=300 type=scheduled"),
            format!("PATCH /meetings/888 agenda=ocg:event:{event_id} topic=Test Meeting"),
            "GET /meetings/888".to_string(),
        ]
    );
    assert_eq!(provider_meeting.id, "888");
    assert_eq!(provider_meeting.host_user_id.as_deref(), Some(OTHER_HOST));
}

#[tokio::test]
async fn test_create_meeting_adopts_meeting_from_last_provider_host_user_removed_from_pool() {
    // Serve a retired host (no longer in host_pool_users) that still owns the earlier meeting
    let event_id = Uuid::new_v4();
    let retired_host = "retired@example.com";
    let calls = Arc::new(Mutex::new(Vec::new()));
    let listings = HashMap::from([
        (
            retired_host.to_string(),
            vec![json!({"meetings": [{"id": 999, "agenda": format!("ocg:event:{event_id}")}]})],
        ),
        (OTHER_HOST.to_string(), vec![json!({"meetings": []})]),
        (ASSIGNED_HOST.to_string(), vec![json!({"meetings": []})]),
    ]);
    let api = spawn_zoom_api(fake_zoom_api(&calls, listings, None)).await;
    let provider = sample_zoom_provider(&api);

    // Retry creating the meeting with the retired owner recorded in last_provider_host_user
    let provider_meeting = provider
        .create_meeting(&sample_retry_meeting(event_id, Some(retired_host)))
        .await
        .expect("meeting to be adopted from retired owner");

    // Check the retired host was scanned first and adopted without listing remaining pool hosts
    let calls = calls.lock().expect("calls lock to be available").clone();
    assert_eq!(
        calls,
        vec![
            format!("GET /users/{retired_host}/meetings page_size=300 type=scheduled"),
            format!("PATCH /meetings/999 agenda=ocg:event:{event_id} topic=Test Meeting"),
            "GET /meetings/999".to_string(),
        ]
    );
    assert_eq!(provider_meeting.id, "999");
    assert_eq!(provider_meeting.host_user_id.as_deref(), Some(retired_host));
}

#[tokio::test]
async fn test_create_meeting_scans_last_provider_host_user_first_on_retry() {
    // Serve a pool where the second pool host owns the meeting from the timed-out attempt
    let event_id = Uuid::new_v4();
    let calls = Arc::new(Mutex::new(Vec::new()));
    let listings = HashMap::from([
        (OTHER_HOST.to_string(), vec![json!({"meetings": []})]),
        (
            ASSIGNED_HOST.to_string(),
            vec![json!({"meetings": [{"id": 666, "agenda": format!("ocg:event:{event_id}")}]})],
        ),
    ]);
    let api = spawn_zoom_api(fake_zoom_api(&calls, listings, None)).await;
    let provider = sample_zoom_provider(&api);

    // Retry creating the meeting with a case-varied last_provider_host_user matching ASSIGNED_HOST
    let provider_meeting = provider
        .create_meeting(&sample_retry_meeting(
            event_id,
            Some("ASSIGNED@EXAMPLE.COM"),
        ))
        .await
        .expect("meeting to be adopted on sticky host");

    // Check ASSIGNED_HOST was scanned first and OTHER_HOST was never listed
    let calls = calls.lock().expect("calls lock to be available").clone();
    assert_eq!(
        calls,
        vec![
            format!("GET /users/{ASSIGNED_HOST}/meetings page_size=300 type=scheduled"),
            format!("PATCH /meetings/666 agenda=ocg:event:{event_id} topic=Test Meeting"),
            "GET /meetings/666".to_string(),
        ]
    );
    assert_eq!(provider_meeting.id, "666");
    assert_eq!(
        provider_meeting.host_user_id.as_deref(),
        Some(ASSIGNED_HOST)
    );
}

#[tokio::test]
async fn test_create_meeting_skips_adoption_scan_on_first_attempt() {
    // Serve a pool whose hosts would be listed if an adoption scan ran
    let event_id = Uuid::new_v4();
    let calls = Arc::new(Mutex::new(Vec::new()));
    let listings = HashMap::from([
        (
            OTHER_HOST.to_string(),
            vec![json!({"meetings": [{"id": 555, "agenda": format!("ocg:event:{event_id}")}]})],
        ),
        (ASSIGNED_HOST.to_string(), vec![json!({"meetings": []})]),
    ]);
    let api = spawn_zoom_api(fake_zoom_api(&calls, listings, None)).await;
    let provider = sample_zoom_provider(&api);

    // Create a brand-new meeting with create_attempted_at unset
    let provider_meeting = provider
        .create_meeting(&sample_meeting(event_id))
        .await
        .expect("meeting to be created directly");

    // Check no host listings were requested before POST create
    let calls = calls.lock().expect("calls lock to be available").clone();
    assert_eq!(
        calls,
        vec![format!(
            "POST /users/{ASSIGNED_HOST}/meetings agenda=ocg:event:{event_id}"
        )]
    );
    assert_eq!(provider_meeting.id, "9001");
    assert_eq!(provider_meeting.join_url, "https://zoom.us/j/9001");
    assert_eq!(
        provider_meeting.host_user_id.as_deref(),
        Some(ASSIGNED_HOST)
    );
    assert_eq!(provider_meeting.password.as_deref(), Some("created-secret"));
}

#[tokio::test]
async fn test_create_meeting_skips_deleted_last_provider_host_user_outside_pool() {
    // Serve a deleted retired host (404 / code 1001) and an empty active host pool
    let event_id = Uuid::new_v4();
    let deleted_host = "deleted@example.com";
    let calls = Arc::new(Mutex::new(Vec::new()));
    let listings = HashMap::from([
        (OTHER_HOST.to_string(), vec![json!({"meetings": []})]),
        (ASSIGNED_HOST.to_string(), vec![json!({"meetings": []})]),
    ]);
    let api = spawn_zoom_api(fake_zoom_api(
        &calls,
        listings,
        Some((deleted_host.to_string(), StatusCode::NOT_FOUND)),
    ))
    .await;
    let provider = sample_zoom_provider(&api);

    // Retry creating the meeting with the deleted retired host as last_provider_host_user
    let provider_meeting = provider
        .create_meeting(&sample_retry_meeting(event_id, Some(deleted_host)))
        .await
        .expect("meeting to be created after treating deleted out-of-pool host as a miss");

    // Check the deleted host was treated as a miss and creation proceeded after scanning the pool
    let calls = calls.lock().expect("calls lock to be available").clone();
    assert_eq!(
        calls,
        vec![
            format!("GET /users/{deleted_host}/meetings page_size=300 type=scheduled"),
            format!("GET /users/{OTHER_HOST}/meetings page_size=300 type=scheduled"),
            format!("GET /users/{ASSIGNED_HOST}/meetings page_size=300 type=scheduled"),
            format!("POST /users/{ASSIGNED_HOST}/meetings agenda=ocg:event:{event_id}"),
        ]
    );
    assert_eq!(provider_meeting.id, "9001");
    assert_eq!(
        provider_meeting.host_user_id.as_deref(),
        Some(ASSIGNED_HOST)
    );
}

#[tokio::test]
async fn test_create_meeting_walks_every_listing_page() {
    // Serve a host whose stamped meeting is only on the second page
    let event_id = Uuid::new_v4();
    let calls = Arc::new(Mutex::new(Vec::new()));
    let listings = HashMap::from([
        (
            OTHER_HOST.to_string(),
            vec![
                json!({"meetings": [{"id": 1}], "next_page_token": "page-2"}),
                json!({"meetings": [{"id": 777, "agenda": format!("ocg:event:{event_id}")}]}),
            ],
        ),
        (ASSIGNED_HOST.to_string(), vec![json!({"meetings": []})]),
    ]);
    let api = spawn_zoom_api(fake_zoom_api(&calls, listings, None)).await;
    let provider = sample_zoom_provider(&api);

    // Retry creating the meeting after a prior create attempt
    let provider_meeting = provider
        .create_meeting(&sample_retry_meeting(event_id, None))
        .await
        .expect("meeting to be adopted");

    // Check the second page was requested with the token from the first one
    let calls = calls.lock().expect("calls lock to be available").clone();
    assert_eq!(
        calls,
        vec![
            format!("GET /users/{OTHER_HOST}/meetings page_size=300 type=scheduled"),
            format!(
                "GET /users/{OTHER_HOST}/meetings next_page_token=page-2 page_size=300 type=scheduled"
            ),
            format!("PATCH /meetings/777 agenda=ocg:event:{event_id} topic=Test Meeting"),
            "GET /meetings/777".to_string(),
        ]
    );
    assert_eq!(provider_meeting.id, "777");
    assert_eq!(provider_meeting.host_user_id.as_deref(), Some(OTHER_HOST));
}

#[tokio::test]
async fn test_end_meeting_skips_end_call_when_meeting_is_not_running() {
    // Serve a meeting whose details report no running status
    let calls = Arc::new(Mutex::new(Vec::new()));
    let api = spawn_zoom_api(fake_zoom_api(&calls, HashMap::new(), None)).await;
    let provider = sample_zoom_provider(&api);

    // End the meeting
    let result = provider.end_meeting("555").await.expect("status check to succeed");

    // Check only the status was read and no end request was sent
    assert!(matches!(result, MeetingEndResult::AlreadyNotRunning));
    let calls = calls.lock().expect("calls lock to be available").clone();
    assert_eq!(calls, vec!["GET /meetings/555".to_string()]);
}

// Helpers.

/// Creates a sample Zoom configuration with the given host pool users.
pub(super) fn sample_zoom_config(host_pool_users: Vec<String>) -> MeetingsZoomConfig {
    MeetingsZoomConfig {
        account_id: "account".to_string(),
        client_id: "client".to_string(),
        client_secret: "secret".to_string(),
        enabled: true,
        host_pool_users,
        max_participants: 100,
        max_simultaneous_meetings_per_host: 1,
        webhook_secret_token: "webhook".to_string(),

        http_client: HttpClientConfig::default(),
    }
}

/// Serves the fake Zoom API on an ephemeral port until the test runtime stops.
pub(super) async fn spawn_zoom_api(router: Router) -> String {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .expect("test Zoom API listener to bind");
    let address = listener
        .local_addr()
        .expect("test Zoom API listener address to exist");
    tokio::spawn(async move {
        axum::serve(listener, router).await.expect("test Zoom API to serve");
    });

    format!("http://{address}")
}

/// Builds a fake Zoom API that records calls and serves the given listings.
///
/// Listings map each host to its pages in order; requests beyond the last
/// page repeat the last one. The optional failure makes listing that host
/// respond with the given status.
fn fake_zoom_api(
    calls: &Arc<Mutex<Vec<String>>>,
    listings: HashMap<String, Vec<Value>>,
    listing_failure: Option<(String, StatusCode)>,
) -> Router {
    let listings = Arc::new(listings);
    let listing_failure = Arc::new(listing_failure);
    let list_calls = Arc::clone(calls);
    let create_calls = Arc::clone(calls);
    let update_calls = Arc::clone(calls);
    let get_calls = Arc::clone(calls);

    Router::new()
        .route(
            "/oauth/token",
            post(|| async { Json(json!({"access_token": "token", "expires_in": 3600})) }),
        )
        .route(
            "/v2/users/{user_id}/meetings",
            get(
                move |Path(user_id): Path<String>, Query(query): Query<HashMap<String, String>>| {
                    let listings = Arc::clone(&listings);
                    let listing_failure = Arc::clone(&listing_failure);
                    let calls = Arc::clone(&list_calls);
                    async move {
                        // Record the call with its sorted query parameters
                        let mut params: Vec<String> =
                            query.iter().map(|(k, v)| format!("{k}={v}")).collect();
                        params.sort();
                        calls.lock().expect("calls lock to be available").push(format!(
                            "GET /users/{user_id}/meetings {}",
                            params.join(" ")
                        ));

                        // Fail the configured host
                        if let Some((failing_host, status)) = listing_failure.as_ref()
                            && *failing_host == user_id
                        {
                            return (
                                *status,
                                Json(json!({"code": 1001, "message": "User does not exist"})),
                            );
                        }

                        // Serve the page matching the token, defaulting to the first one
                        let pages = listings.get(&user_id).cloned().unwrap_or_default();
                        let page_index = query
                            .get("next_page_token")
                            .and_then(|token| token.strip_prefix("page-"))
                            .and_then(|n| n.parse::<usize>().ok())
                            .map_or(0, |n| n.saturating_sub(1));
                        let page = pages
                            .get(page_index)
                            .or(pages.last())
                            .cloned()
                            .unwrap_or_else(|| json!({"meetings": []}));
                        (StatusCode::OK, Json(page))
                    }
                },
            )
            .post(
                move |Path(user_id): Path<String>, Json(body): Json<Value>| {
                    let calls = Arc::clone(&create_calls);
                    async move {
                        calls.lock().expect("calls lock to be available").push(format!(
                            "POST /users/{user_id}/meetings agenda={}",
                            body["agenda"].as_str().unwrap_or_default()
                        ));
                        (
                            StatusCode::CREATED,
                            Json(json!({
                                "id": 9001,
                                "join_url": "https://zoom.us/j/9001",
                                "password": "created-secret",
                            })),
                        )
                    }
                },
            ),
        )
        .route(
            "/v2/meetings/{meeting_id}",
            get(move |Path(meeting_id): Path<i64>| {
                let calls = Arc::clone(&get_calls);
                async move {
                    calls
                        .lock()
                        .expect("calls lock to be available")
                        .push(format!("GET /meetings/{meeting_id}"));
                    Json(json!({
                        "id": meeting_id,
                        "join_url": format!("https://zoom.us/j/{meeting_id}"),
                        "password": "existing-secret",
                    }))
                }
            })
            .patch(
                move |Path(meeting_id): Path<i64>, Json(body): Json<Value>| {
                    let calls = Arc::clone(&update_calls);
                    async move {
                        calls.lock().expect("calls lock to be available").push(format!(
                            "PATCH /meetings/{meeting_id} agenda={} topic={}",
                            body["agenda"].as_str().unwrap_or_default(),
                            body["topic"].as_str().unwrap_or_default()
                        ));
                        StatusCode::NO_CONTENT
                    }
                },
            ),
        )
}

/// Creates a meeting owned by the given event and reserved on the assigned host.
fn sample_meeting(event_id: Uuid) -> Meeting {
    Meeting {
        duration: Some(Duration::from_mins(30)),
        event_id: Some(event_id),
        provider_host_user_id: Some(ASSIGNED_HOST.to_string()),
        starts_at: Some(chrono::DateTime::from_timestamp(1_900_000_000, 0).unwrap()),
        topic: Some("Test Meeting".to_string()),
        ..Default::default()
    }
}

/// Creates a retry-path meeting whose create was already attempted earlier.
fn sample_retry_meeting(event_id: Uuid, last_provider_host_user: Option<&str>) -> Meeting {
    Meeting {
        create_attempted_at: Some(chrono::DateTime::from_timestamp(1_899_999_000, 0).unwrap()),
        last_provider_host_user: last_provider_host_user.map(str::to_string),
        ..sample_meeting(event_id)
    }
}

/// Creates a Zoom provider pointed at the fake API without request throttling.
fn sample_zoom_provider(api_address: &str) -> ZoomMeetingsProvider {
    let mut provider = ZoomMeetingsProvider::new(&sample_zoom_config(vec![
        OTHER_HOST.to_string(),
        ASSIGNED_HOST.to_string(),
    ]))
    .expect("sample Zoom provider to build");
    provider.client.api_base_url = format!("{api_address}/v2");
    provider.client.request_interval = Duration::ZERO;
    provider.client.token_url = format!("{api_address}/oauth/token");

    provider
}
