use anyhow::anyhow;
use axum::{
    body::{Body, to_bytes},
    http::{
        HeaderValue, Request, StatusCode,
        header::{COOKIE, LOCATION},
    },
};
use axum_login::tower_sessions::session;
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::tests::*,
    services::{notifications::MockNotificationsManager, payments::MockPaymentsManager},
    templates::dashboard::{DASHBOARD_PAGINATION_LIMIT, user::purchases::PurchaseDocumentsOutput},
};

#[tokio::test]
async fn test_credit_note_document_returns_not_found_when_document_is_unavailable() {
    // Setup an authenticated document request
    let event_purchase_credit_note_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);

    // Return no attendee-owned document from the payments service
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_get_purchase_document_url()
        .times(1)
        .withf(move |uid, purchase_id, credit_note_id| {
            *uid == user_id
                && *purchase_id == event_purchase_id
                && *credit_note_id == Some(event_purchase_credit_note_id)
        })
        .returning(|_, _, _| Box::pin(async { Ok(None) }));

    // Request the unavailable credit note
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!(
            "/dashboard/user/purchases/{event_purchase_id}/credit-notes/{event_purchase_credit_note_id}"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check unavailable documents remain hidden
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_credit_note_document_success() {
    // Setup an authenticated credit-note request
    let event_purchase_credit_note_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);

    // Return the current account-scoped provider URL
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_get_purchase_document_url()
        .times(1)
        .withf(move |uid, purchase_id, credit_note_id| {
            *uid == user_id
                && *purchase_id == event_purchase_id
                && *credit_note_id == Some(event_purchase_credit_note_id)
        })
        .returning(|_, _, _| {
            Box::pin(async { Ok(Some("https://payments.test/credit-note".to_string())) })
        });

    // Request the credit-note document
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!(
            "/dashboard/user/purchases/{event_purchase_id}/credit-notes/{event_purchase_credit_note_id}"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the attendee is redirected to the fresh provider document
    assert_empty_response(&parts, &bytes, StatusCode::TEMPORARY_REDIRECT);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static(
            "https://payments.test/credit-note"
        )),
    );
}

#[tokio::test]
async fn test_invoice_document_returns_internal_server_error_when_payments_manager_fails() {
    // Setup an authenticated invoice request
    let event_purchase_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);

    // Fail the provider document lookup
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_get_purchase_document_url()
        .times(1)
        .withf(move |uid, purchase_id, credit_note_id| {
            *uid == user_id && *purchase_id == event_purchase_id && credit_note_id.is_none()
        })
        .returning(|_, _, _| Box::pin(async { Err(anyhow!("payments error")) }));

    // Request the invoice document
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!(
            "/dashboard/user/purchases/{event_purchase_id}/invoice"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the provider failure remains visible
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_invoice_document_success() {
    // Setup an authenticated invoice request
    let event_purchase_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);

    // Return the current account-scoped provider URL
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_get_purchase_document_url()
        .times(1)
        .withf(move |uid, purchase_id, credit_note_id| {
            *uid == user_id && *purchase_id == event_purchase_id && credit_note_id.is_none()
        })
        .returning(|_, _, _| {
            Box::pin(async { Ok(Some("https://payments.test/invoice".to_string())) })
        });

    // Request the invoice document
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri(format!(
            "/dashboard/user/purchases/{event_purchase_id}/invoice"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the attendee is redirected to the fresh provider document
    assert_empty_response(&parts, &bytes, StatusCode::TEMPORARY_REDIRECT);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static("https://payments.test/invoice")),
    );
}

#[tokio::test]
async fn test_list_page_db_error() {
    // Setup an authenticated list request
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_list_user_purchase_documents()
        .times(1)
        .withf(move |uid, filters| {
            *uid == user_id
                && filters.limit == Some(DASHBOARD_PAGINATION_LIMIT)
                && filters.offset == Some(0)
        })
        .returning(|_, _| Err(anyhow!("db error")));

    // Request the purchase-document partial
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/user/purchases")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check the database failure remains visible
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_list_page_success() {
    // Setup an authenticated paginated list request
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_list_user_purchase_documents()
        .times(1)
        .withf(move |uid, filters| {
            *uid == user_id && filters.limit == Some(5) && filters.offset == Some(10)
        })
        .returning(|_, _| {
            Ok(PurchaseDocumentsOutput {
                purchases: Vec::new(),
                total: 0,
            })
        });

    // Request the purchase-document partial with pagination
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/user/purchases?limit=5&offset=10")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the partial and browser navigation URL
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url"),
        Some(&HeaderValue::from_static(
            "/dashboard/user?tab=purchases&limit=5&offset=10"
        )),
    );
    assert!(body.contains("No paid-ticket documents yet"));
}
