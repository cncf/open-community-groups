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
use tokio::task::JoinHandle;
use uuid::Uuid;

use crate::{
    config::{HttpClientConfig, MeetingsZoomConfig},
    services::meetings::{MeetingProviderError, MeetingsProvider},
    types::meetings::Meeting,
};

use super::ZoomMeetingsProvider;

/// Host reserved for the meeting under test.
const ASSIGNED_HOST: &str = "assigned@example.com";

/// Other host in the pool, listed before the assigned one.
const OTHER_HOST: &str = "other@example.com";

#[tokio::test]
async fn create_meeting_creates_when_no_host_has_the_reference() {
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
    let (api, server) = spawn_zoom_api(fake_zoom_api(&calls, listings, None)).await;
    let provider = sample_zoom_provider(&api);

    // Create the meeting
    let provider_meeting = provider
        .create_meeting(&sample_meeting(event_id))
        .await
        .expect("meeting to be created");
    server.abort();

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
async fn create_meeting_adopts_meeting_found_on_another_host() {
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
    let (api, server) = spawn_zoom_api(fake_zoom_api(&calls, listings, None)).await;
    let provider = sample_zoom_provider(&api);

    // Create the meeting
    let provider_meeting = provider
        .create_meeting(&sample_meeting(event_id))
        .await
        .expect("meeting to be adopted");
    server.abort();

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
async fn create_meeting_walks_every_listing_page() {
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
    let (api, server) = spawn_zoom_api(fake_zoom_api(&calls, listings, None)).await;
    let provider = sample_zoom_provider(&api);

    // Create the meeting
    let provider_meeting = provider
        .create_meeting(&sample_meeting(event_id))
        .await
        .expect("meeting to be adopted");
    server.abort();

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
async fn create_meeting_fails_instead_of_creating_when_a_listing_fails() {
    // Serve a pool where one host cannot be listed
    let event_id = Uuid::new_v4();
    let calls = Arc::new(Mutex::new(Vec::new()));
    let listings = HashMap::from([(ASSIGNED_HOST.to_string(), vec![json!({"meetings": []})])]);
    let (api, server) = spawn_zoom_api(fake_zoom_api(
        &calls,
        listings,
        Some((OTHER_HOST.to_string(), StatusCode::NOT_FOUND)),
    ))
    .await;
    let provider = sample_zoom_provider(&api);

    // Create the meeting
    let err = provider
        .create_meeting(&sample_meeting(event_id))
        .await
        .expect_err("listing failure to fail the creation");
    server.abort();

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

/// Creates a Zoom provider pointed at the fake API without request throttling.
fn sample_zoom_provider(api_address: &str) -> ZoomMeetingsProvider {
    let mut provider = ZoomMeetingsProvider::new(&MeetingsZoomConfig {
        account_id: "account".to_string(),
        client_id: "client".to_string(),
        client_secret: "secret".to_string(),
        enabled: true,
        host_pool_users: vec![OTHER_HOST.to_string(), ASSIGNED_HOST.to_string()],
        max_participants: 100,
        max_simultaneous_meetings_per_host: 1,
        webhook_secret_token: "webhook".to_string(),

        http_client: HttpClientConfig::default(),
    })
    .expect("sample Zoom provider to build");
    provider.client.api_base_url = format!("{api_address}/v2");
    provider.client.request_interval = Duration::ZERO;
    provider.client.token_url = format!("{api_address}/oauth/token");

    provider
}

/// Serves the fake Zoom API on an ephemeral port.
async fn spawn_zoom_api(router: Router) -> (String, JoinHandle<()>) {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .expect("test Zoom API listener to bind");
    let address = listener
        .local_addr()
        .expect("test Zoom API listener address to exist");
    let server = tokio::spawn(async move {
        axum::serve(listener, router).await.expect("test Zoom API to serve");
    });

    (format!("http://{address}"), server)
}
