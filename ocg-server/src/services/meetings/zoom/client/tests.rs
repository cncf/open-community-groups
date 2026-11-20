use std::{
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicUsize, Ordering},
    },
    time::Duration,
};

use axum::{
    Json, Router,
    extract::{Path, State},
    http::{
        self, HeaderMap, StatusCode,
        header::{AUTHORIZATION, RETRY_AFTER},
    },
    response::IntoResponse,
    routing::{get, post, put},
};
use serde_json::{Value, json};
use tokio::sync::{Barrier, Notify};

use crate::{services::meetings::MeetingProviderError, types::meetings::Meeting};

use super::{
    super::tests::{sample_zoom_config, spawn_zoom_api},
    CreateMeetingRequest, MAX_DURATION_MINUTES, MIN_DURATION_MINUTES, Minutes,
    UpdateMeetingRequest, ZoomClient, ZoomClientError,
};

#[tokio::test]
async fn test_authenticated_methods_refresh_token_and_retry_once_on_unauthorized() {
    let methods = [
        "create_meeting",
        "delete_meeting",
        "end_meeting",
        "get_meeting",
        "list_meetings",
        "update_meeting",
    ];

    for method in methods {
        // Setup fake Zoom API rejecting token-1 with 401 and accepting token-2
        let token_fetches = Arc::new(AtomicUsize::new(0));
        let api_calls = Arc::new(Mutex::new(Vec::new()));
        let api = spawn_zoom_api(fake_retry_zoom_api(&token_fetches, &api_calls)).await;
        let client = sample_zoom_client(&api);

        // Execute the method and verify its response
        let expected_call = match method {
            "create_meeting" => {
                let req = CreateMeetingRequest {
                    meeting_type: 2,
                    topic: "Retry Topic".to_string(),

                    agenda: Some("ocg:event:test".to_string()),
                    default_password: Some(true),
                    duration: None,
                    settings: None,
                    start_time: None,
                    timezone: None,
                };
                let meeting = client
                    .create_meeting("host@example.com", &req)
                    .await
                    .expect("create_meeting to succeed after refresh");
                assert_eq!(meeting.id, 9001, "{method}");
                assert_eq!(meeting.join_url, "https://zoom.us/j/9001", "{method}");
                "POST /users/host@example.com/meetings topic=Retry Topic"
            }
            "delete_meeting" => {
                client
                    .delete_meeting(555)
                    .await
                    .expect("delete_meeting to succeed after refresh");
                "DELETE /meetings/555"
            }
            "end_meeting" => {
                client
                    .end_meeting(555)
                    .await
                    .expect("end_meeting to succeed after refresh");
                "PUT /meetings/555/status action=end"
            }
            "get_meeting" => {
                let meeting = client
                    .get_meeting(555)
                    .await
                    .expect("get_meeting to succeed after refresh");
                assert_eq!(meeting.id, 555, "{method}");
                assert_eq!(meeting.join_url, "https://zoom.us/j/555", "{method}");
                "GET /meetings/555"
            }
            "list_meetings" => {
                let page = client
                    .list_meetings("host@example.com", None)
                    .await
                    .expect("list_meetings to succeed after refresh");
                assert_eq!(page.meetings.len(), 1, "{method}");
                assert_eq!(page.meetings[0].id, 777, "{method}");
                "GET /users/host@example.com/meetings"
            }
            "update_meeting" => {
                let req = UpdateMeetingRequest {
                    topic: Some("Updated Topic".to_string()),
                    ..Default::default()
                };
                client
                    .update_meeting(555, &req)
                    .await
                    .expect("update_meeting to succeed after refresh");
                "PATCH /meetings/555 topic=Updated Topic"
            }
            _ => unreachable!("unexpected method {method}"),
        };

        // Check token was refreshed once and the method retried with token-2
        assert_eq!(token_fetches.load(Ordering::SeqCst), 2, "{method}");
        let calls = api_calls.lock().expect("api calls lock").clone();
        assert_eq!(
            calls,
            vec![
                format!("{expected_call} auth=Bearer token-1"),
                format!("{expected_call} auth=Bearer token-2"),
            ],
            "{method}"
        );

        // Check subsequent requests reuse the refreshed token without another fetch
        client
            .get_meeting(555)
            .await
            .expect("follow-up request to reuse refreshed token");
        assert_eq!(
            token_fetches.load(Ordering::SeqCst),
            2,
            "{method} follow-up"
        );
    }
}

#[tokio::test]
async fn test_concurrent_unauthorized_responses_trigger_single_token_refresh() {
    // Setup fake Zoom API where token-1 can be revoked after priming and concurrent 401s align
    let token_fetches = Arc::new(AtomicUsize::new(0));
    let token_1_revoked = Arc::new(AtomicBool::new(false));
    let auth_headers = Arc::new(Mutex::new(Vec::new()));
    let unauthorized_barrier = Arc::new(Barrier::new(2));

    let router = fake_token_router(&token_fetches).route(
        "/v2/meetings/{meeting_id}",
        get({
            let token_1_revoked = Arc::clone(&token_1_revoked);
            let auth_headers = Arc::clone(&auth_headers);
            let unauthorized_barrier = Arc::clone(&unauthorized_barrier);
            move |Path(meeting_id): Path<i64>, headers: HeaderMap| {
                let token_1_revoked = Arc::clone(&token_1_revoked);
                let auth_headers = Arc::clone(&auth_headers);
                let unauthorized_barrier = Arc::clone(&unauthorized_barrier);
                async move {
                    let auth = bearer_header(&headers);
                    auth_headers.lock().expect("auth headers lock").push(auth.clone());

                    // Synchronize both revoked token-1 requests so they receive 401 together
                    if token_1_revoked.load(Ordering::SeqCst) && auth == "Bearer token-1" {
                        unauthorized_barrier.wait().await;
                        return unauthorized_response();
                    }

                    meeting_ok_response(meeting_id)
                }
            }
        }),
    );
    let api = spawn_zoom_api(router).await;
    let client = sample_zoom_client(&api);

    // Prime the client cache with token-1, then revoke token-1
    let primed = client.get_meeting(1).await.expect("priming call to succeed");
    assert_eq!(primed.id, 1);
    assert_eq!(token_fetches.load(Ordering::SeqCst), 1);
    token_1_revoked.store(true, Ordering::SeqCst);

    // Run two concurrent requests with the revoked cached token
    let (first, second) = tokio::time::timeout(Duration::from_secs(5), async {
        tokio::join!(client.get_meeting(10), client.get_meeting(20))
    })
    .await
    .expect("concurrent requests to complete without deadlocking");

    // Check both requests succeeded and triggered only one token refresh
    assert_eq!(first.expect("first request to succeed").id, 10);
    assert_eq!(second.expect("second request to succeed").id, 20);
    assert_eq!(token_fetches.load(Ordering::SeqCst), 2);
    let headers = auth_headers.lock().expect("auth headers lock").clone();
    assert_eq!(
        headers.iter().filter(|h| h.as_str() == "Bearer token-1").count(),
        3
    );
    assert_eq!(
        headers.iter().filter(|h| h.as_str() == "Bearer token-2").count(),
        2
    );
}

#[tokio::test]
async fn test_delayed_unauthorized_does_not_clear_refreshed_token() {
    // Setup fake Zoom API where one token-1 401 is delayed until after another call refreshes
    let token_fetches = Arc::new(AtomicUsize::new(0));
    let token_1_revoked = Arc::new(AtomicBool::new(false));
    let delayed_arrived = Arc::new(Notify::new());
    let release_delayed = Arc::new(Notify::new());

    let router = fake_token_router(&token_fetches).route(
        "/v2/meetings/{meeting_id}",
        get({
            let token_1_revoked = Arc::clone(&token_1_revoked);
            let delayed_arrived = Arc::clone(&delayed_arrived);
            let release_delayed = Arc::clone(&release_delayed);
            move |Path(meeting_id): Path<i64>, headers: HeaderMap| {
                let token_1_revoked = Arc::clone(&token_1_revoked);
                let delayed_arrived = Arc::clone(&delayed_arrived);
                let release_delayed = Arc::clone(&release_delayed);
                async move {
                    let auth = bearer_header(&headers);
                    if token_1_revoked.load(Ordering::SeqCst) && auth == "Bearer token-1" {
                        if meeting_id == 20 {
                            delayed_arrived.notify_one();
                            release_delayed.notified().await;
                        }
                        return unauthorized_response();
                    }
                    if auth == "Bearer token-2" || !token_1_revoked.load(Ordering::SeqCst) {
                        return meeting_ok_response(meeting_id);
                    }
                    unauthorized_response()
                }
            }
        }),
    );
    let api = spawn_zoom_api(router).await;
    let client = sample_zoom_client(&api);

    // Prime the cache with token-1, then revoke token-1
    client.get_meeting(1).await.expect("priming call to succeed");
    assert_eq!(token_fetches.load(Ordering::SeqCst), 1);
    token_1_revoked.store(true, Ordering::SeqCst);

    // Start the delayed call on token-1, complete a refresh via another call, then release the 401
    let (delayed, refreshed) = tokio::time::timeout(Duration::from_secs(5), async {
        tokio::join!(client.get_meeting(20), async {
            delayed_arrived.notified().await;
            let result = client.get_meeting(10).await;
            release_delayed.notify_one();
            result
        })
    })
    .await
    .expect("delayed 401 test to complete without deadlocking");

    // Check the delayed 401 preserved token-2 and did not trigger a second refresh
    assert_eq!(refreshed.expect("refreshing call to succeed").id, 10);
    assert_eq!(
        delayed.expect("delayed call to succeed with token-2").id,
        20
    );
    assert_eq!(token_fetches.load(Ordering::SeqCst), 2);
}

#[tokio::test]
async fn test_forbidden_does_not_invalidate_token_or_retry() {
    // Setup fake Zoom API returning 403 for meeting 403 and 200 for meeting 200
    let token_fetches = Arc::new(AtomicUsize::new(0));
    let auth_headers = Arc::new(Mutex::new(Vec::new()));

    let router = fake_token_router(&token_fetches).route(
        "/v2/meetings/{meeting_id}",
        get({
            let auth_headers = Arc::clone(&auth_headers);
            move |Path(meeting_id): Path<i64>, headers: HeaderMap| {
                let auth_headers = Arc::clone(&auth_headers);
                async move {
                    auth_headers
                        .lock()
                        .expect("auth headers lock")
                        .push(bearer_header(&headers));
                    if meeting_id == 403 {
                        return (
                            StatusCode::FORBIDDEN,
                            Json(json!({"code": 200, "message": "No permission"})),
                        )
                            .into_response();
                    }
                    meeting_ok_response(meeting_id)
                }
            }
        }),
    );
    let api = spawn_zoom_api(router).await;
    let client = sample_zoom_client(&api);

    // Call the forbidden endpoint
    let err = client.get_meeting(403).await.expect_err("403 response to fail");

    // Check 403 returned a token error without retrying or refreshing
    assert!(
        matches!(err, ZoomClientError::Token(ref msg) if msg == "200 - No permission"),
        "{err}"
    );
    assert_eq!(token_fetches.load(Ordering::SeqCst), 1);
    assert_eq!(
        auth_headers.lock().expect("auth headers lock").clone(),
        vec!["Bearer token-1".to_string()]
    );

    // Check the cached token-1 was preserved for subsequent calls
    let meeting = client
        .get_meeting(200)
        .await
        .expect("subsequent call to reuse cached token");
    assert_eq!(meeting.id, 200);
    assert_eq!(token_fetches.load(Ordering::SeqCst), 1);
    assert_eq!(
        auth_headers.lock().expect("auth headers lock").clone(),
        vec!["Bearer token-1".to_string(), "Bearer token-1".to_string()]
    );
}

#[tokio::test]
async fn test_from_response_classifies_status_into_provider_errors() {
    let cases = [
        (
            "rate limited with retry-after",
            StatusCode::TOO_MANY_REQUESTS,
            Some("45"),
            json!({}),
            "rate limit exceeded (retry after 45s)",
            Some(Duration::from_secs(45)),
        ),
        (
            "rate limited without retry-after",
            StatusCode::TOO_MANY_REQUESTS,
            None,
            json!({}),
            "rate limit exceeded (retry after 60s)",
            Some(Duration::from_mins(1)),
        ),
        (
            "unauthorized",
            StatusCode::UNAUTHORIZED,
            None,
            json!({"code": 124, "message": "Invalid access token"}),
            "provider token error: 124 - Invalid access token",
            None,
        ),
        (
            "forbidden",
            StatusCode::FORBIDDEN,
            None,
            json!({"code": 200, "message": "No permission"}),
            "provider token error: 200 - No permission",
            None,
        ),
        (
            "other client error",
            StatusCode::NOT_FOUND,
            None,
            json!({"code": 1001, "message": "User does not exist"}),
            "provider client error: 1001: User does not exist",
            None,
        ),
        (
            "meeting not found",
            StatusCode::NOT_FOUND,
            None,
            json!({"code": 3001, "message": "Meeting does not exist"}),
            "meeting not found",
            None,
        ),
        (
            "server error without a body",
            StatusCode::SERVICE_UNAVAILABLE,
            None,
            json!(null),
            "provider server error: 0: ",
            None,
        ),
    ];
    for (case, status, retry_after_header, body, message, retry_after) in cases {
        // Build the response the Zoom API would return
        let mut response = http::Response::builder().status(status);
        if let Some(retry_after_header) = retry_after_header {
            response = response.header(RETRY_AFTER, retry_after_header);
        }
        let response = reqwest::Response::from(response.body(body.to_string()).unwrap());

        // Check the provider error it maps to
        let err = MeetingProviderError::from(ZoomClientError::from_response(response).await);
        assert_eq!(err.to_string(), message, "{case}");
        assert_eq!(err.retry_after(), retry_after, "{case}");
    }
}

#[test]
fn test_meeting_requests_map_recording_preference_to_auto_recording() {
    let cases = [
        ("recording requested", Some(true), "cloud"),
        ("recording preference unset", None, "cloud"),
        ("recording declined", Some(false), "none"),
    ];
    for (case, recording_requested, auto_recording) in cases {
        let meeting = Meeting {
            recording_requested,
            ..Default::default()
        };

        // Check create and update requests apply the same recording setting
        let create = serde_json::to_value(CreateMeetingRequest::try_from(&meeting).unwrap());
        assert_eq!(
            create.unwrap()["settings"]["auto_recording"],
            json!(auto_recording),
            "{case} create"
        );
        let update = serde_json::to_value(UpdateMeetingRequest::try_from(&meeting).unwrap());
        assert_eq!(
            update.unwrap()["settings"]["auto_recording"],
            json!(auto_recording),
            "{case} update"
        );
    }
}

#[test]
fn test_minutes_try_from_duration_enforces_provider_bounds() {
    let cases = [
        ("below minimum", MIN_DURATION_MINUTES - 1, false),
        ("minimum", MIN_DURATION_MINUTES, true),
        ("maximum", MAX_DURATION_MINUTES, true),
        ("above maximum", MAX_DURATION_MINUTES + 1, false),
    ];
    for (case, minutes, accepted) in cases {
        let duration = Duration::from_mins(u64::try_from(minutes).unwrap());
        match Minutes::try_from_duration(duration) {
            Ok(Minutes(converted)) => {
                assert!(accepted, "{case}");
                assert_eq!(converted, minutes, "{case}");
            }
            Err(err) => {
                assert!(!accepted, "{case}");
                assert_eq!(
                    err.to_string(),
                    format!("invalid meeting duration: {minutes} minutes"),
                    "{case}"
                );
            }
        }
    }
}

#[tokio::test]
async fn test_unauthorized_propagates_token_refresh_failure() {
    // Setup fake Zoom API that rejects token-1 and fails the refresh request
    let token_fetches = Arc::new(AtomicUsize::new(0));
    let api_calls = Arc::new(AtomicUsize::new(0));

    let router = {
        let token_fetches = Arc::clone(&token_fetches);
        let api_calls = Arc::clone(&api_calls);

        Router::new()
            .route(
                "/oauth/token",
                post(move || {
                    let token_fetches = Arc::clone(&token_fetches);
                    async move {
                        let count = token_fetches.fetch_add(1, Ordering::SeqCst) + 1;
                        if count == 1 {
                            return (
                                StatusCode::OK,
                                Json(json!({"access_token": "token-1", "expires_in": 3600})),
                            )
                                .into_response();
                        }
                        (
                            StatusCode::INTERNAL_SERVER_ERROR,
                            Json(json!({"code": 100, "message": "oauth down"})),
                        )
                            .into_response()
                    }
                }),
            )
            .route(
                "/v2/meetings/{meeting_id}",
                get(move || {
                    let api_calls = Arc::clone(&api_calls);
                    async move {
                        api_calls.fetch_add(1, Ordering::SeqCst);
                        unauthorized_response()
                    }
                }),
            )
    };
    let api = spawn_zoom_api(router).await;
    let client = sample_zoom_client(&api);

    // Call the endpoint and check the refresh failure surfaces as a token error
    let err = client
        .get_meeting(123)
        .await
        .expect_err("failed token refresh to fail request");
    assert!(
        matches!(err, ZoomClientError::Token(ref msg) if msg == "zoom token error: 100 - oauth down"),
        "{err}"
    );
    assert_eq!(token_fetches.load(Ordering::SeqCst), 2);
    assert_eq!(api_calls.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn test_unauthorized_retries_at_most_once_and_returns_token_error() {
    // Setup fake Zoom API that always rejects requests with 401
    let token_fetches = Arc::new(AtomicUsize::new(0));
    let auth_headers = Arc::new(Mutex::new(Vec::new()));

    let router = fake_token_router(&token_fetches).route(
        "/v2/meetings/{meeting_id}",
        get({
            let auth_headers = Arc::clone(&auth_headers);
            move |headers: HeaderMap| {
                let auth_headers = Arc::clone(&auth_headers);
                async move {
                    auth_headers
                        .lock()
                        .expect("auth headers lock")
                        .push(bearer_header(&headers));
                    unauthorized_response()
                }
            }
        }),
    );
    let api = spawn_zoom_api(router).await;
    let client = sample_zoom_client(&api);

    // Call the endpoint and check it retries once then returns ZoomClientError::Token
    let err = client
        .get_meeting(123)
        .await
        .expect_err("persistent 401 to fail after one retry");
    assert!(
        matches!(err, ZoomClientError::Token(ref msg) if msg == "124 - Invalid access token"),
        "{err}"
    );
    assert_eq!(token_fetches.load(Ordering::SeqCst), 2);
    assert_eq!(
        auth_headers.lock().expect("auth headers lock").clone(),
        vec!["Bearer token-1".to_string(), "Bearer token-2".to_string()]
    );
}

// Helpers.

/// Extracts the Authorization header as a string for test assertions.
fn bearer_header(headers: &HeaderMap) -> String {
    headers
        .get(AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default()
        .to_string()
}

/// Builds a fake Zoom API covering all 6 endpoints that rejects token-1 and accepts token-2.
fn fake_retry_zoom_api(
    token_fetches: &Arc<AtomicUsize>,
    api_calls: &Arc<Mutex<Vec<String>>>,
) -> Router {
    let api_routes = Router::new()
        .route(
            "/v2/users/{user_id}/meetings",
            get(
                |State(calls): State<Arc<Mutex<Vec<String>>>>,
                 Path(user_id): Path<String>,
                 headers: HeaderMap| async move {
                    let label = format!("GET /users/{user_id}/meetings");
                    respond_with_token_2(&calls, &label, &headers, || {
                        let body = json!({"meetings": [{"id": 777, "agenda": "ocg:event:test"}]});
                        (StatusCode::OK, Json(body)).into_response()
                    })
                },
            )
            .post(
                |State(calls): State<Arc<Mutex<Vec<String>>>>,
                 Path(user_id): Path<String>,
                 headers: HeaderMap,
                 Json(body): Json<Value>| async move {
                    let topic = body["topic"].as_str().unwrap_or_default();
                    let label = format!("POST /users/{user_id}/meetings topic={topic}");
                    respond_with_token_2(&calls, &label, &headers, || {
                        let meeting = json!({
                            "id": 9001,
                            "join_url": "https://zoom.us/j/9001",
                            "password": "created-secret",
                        });
                        (StatusCode::CREATED, Json(meeting)).into_response()
                    })
                },
            ),
        )
        .route(
            "/v2/meetings/{meeting_id}",
            get(
                |State(calls): State<Arc<Mutex<Vec<String>>>>,
                 Path(meeting_id): Path<i64>,
                 headers: HeaderMap| async move {
                    let label = format!("GET /meetings/{meeting_id}");
                    respond_with_token_2(&calls, &label, &headers, || {
                        meeting_ok_response(meeting_id)
                    })
                },
            )
            .delete(
                |State(calls): State<Arc<Mutex<Vec<String>>>>,
                 Path(meeting_id): Path<i64>,
                 headers: HeaderMap| async move {
                    let label = format!("DELETE /meetings/{meeting_id}");
                    respond_with_token_2(&calls, &label, &headers, || {
                        StatusCode::NO_CONTENT.into_response()
                    })
                },
            )
            .patch(
                |State(calls): State<Arc<Mutex<Vec<String>>>>,
                 Path(meeting_id): Path<i64>,
                 headers: HeaderMap,
                 Json(body): Json<Value>| async move {
                    let topic = body["topic"].as_str().unwrap_or_default();
                    let label = format!("PATCH /meetings/{meeting_id} topic={topic}");
                    respond_with_token_2(&calls, &label, &headers, || {
                        StatusCode::NO_CONTENT.into_response()
                    })
                },
            ),
        )
        .route(
            "/v2/meetings/{meeting_id}/status",
            put(
                |State(calls): State<Arc<Mutex<Vec<String>>>>,
                 Path(meeting_id): Path<i64>,
                 headers: HeaderMap,
                 Json(body): Json<Value>| async move {
                    let action = body["action"].as_str().unwrap_or_default();
                    let label = format!("PUT /meetings/{meeting_id}/status action={action}");
                    respond_with_token_2(&calls, &label, &headers, || {
                        StatusCode::NO_CONTENT.into_response()
                    })
                },
            ),
        )
        .with_state(Arc::clone(api_calls));

    fake_token_router(token_fetches).merge(api_routes)
}

/// Builds a router serving sequential OAuth tokens (`token-1`, `token-2`, ...).
fn fake_token_router(token_fetches: &Arc<AtomicUsize>) -> Router {
    let token_fetches = Arc::clone(token_fetches);
    Router::new().route(
        "/oauth/token",
        post(move || {
            let token_fetches = Arc::clone(&token_fetches);
            async move {
                let count = token_fetches.fetch_add(1, Ordering::SeqCst) + 1;
                Json(json!({"access_token": format!("token-{count}"), "expires_in": 3600}))
            }
        }),
    )
}

/// Builds a 200 OK response containing a Zoom meeting payload.
fn meeting_ok_response(meeting_id: i64) -> axum::response::Response {
    (
        StatusCode::OK,
        Json(json!({
            "id": meeting_id,
            "join_url": format!("https://zoom.us/j/{meeting_id}"),
            "password": "secret",
        })),
    )
        .into_response()
}

/// Records an API call with its auth header and succeeds only when presented `Bearer token-2`.
fn respond_with_token_2(
    api_calls: &Arc<Mutex<Vec<String>>>,
    label: &str,
    headers: &HeaderMap,
    on_authorized: impl FnOnce() -> axum::response::Response,
) -> axum::response::Response {
    let auth = bearer_header(headers);
    api_calls
        .lock()
        .expect("api calls lock")
        .push(format!("{label} auth={auth}"));
    if auth != "Bearer token-2" {
        return unauthorized_response();
    }
    on_authorized()
}

/// Creates a Zoom client pointed at the fake API without request throttling.
fn sample_zoom_client(api_address: &str) -> ZoomClient {
    let mut client = ZoomClient::new(sample_zoom_config(vec!["host@example.com".to_string()]))
        .expect("sample Zoom client to build");
    client.api_base_url = format!("{api_address}/v2");
    client.request_interval = Duration::ZERO;
    client.token_url = format!("{api_address}/oauth/token");

    client
}

/// Builds a 401 Unauthorized response matching Zoom's invalid-token error shape.
fn unauthorized_response() -> axum::response::Response {
    (
        StatusCode::UNAUTHORIZED,
        Json(json!({"code": 124, "message": "Invalid access token"})),
    )
        .into_response()
}
