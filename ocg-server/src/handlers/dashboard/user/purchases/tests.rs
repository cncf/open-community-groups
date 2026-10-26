use axum::http::{HeaderValue, StatusCode, header::LOCATION};
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::{error::HandlerError, tests::*},
    services::payments::MockPaymentsManager,
    types::dashboard::user::purchases::PurchaseDocumentsOutput,
};

#[tokio::test]
async fn test_credit_note_document_returns_manager_rejection() {
    // Setup an authenticated credit-note request
    let event_purchase_credit_note_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);

    // Reject the document lookup with a user-facing message
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_get_purchase_document_url()
        .times(1)
        .returning(|_, _, _| {
            Box::pin(async {
                Err(HandlerError::Database("credit note is not issued yet".to_string()).into())
            })
        });

    // Request the credit-note document
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = get_request(
        &format!(
            "/dashboard/user/purchases/{event_purchase_id}/credit-notes/{event_purchase_credit_note_id}"
        ),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), b"credit note is not issued yet");
}

#[tokio::test]
async fn test_credit_note_document_returns_not_found_when_document_is_unavailable() {
    // Setup an authenticated document request
    let event_purchase_credit_note_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);

    // Return no attendee-owned document from the payments service
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_get_purchase_document_url()
        .times(1)
        .withf(move |uid, purchase_id, credit_note_id| {
            *uid == ids.user_id
                && *purchase_id == event_purchase_id
                && *credit_note_id == Some(event_purchase_credit_note_id)
        })
        .returning(|_, _, _| Box::pin(async { Ok(None) }));

    // Request the unavailable credit note
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = get_request(
        &format!(
            "/dashboard/user/purchases/{event_purchase_id}/credit-notes/{event_purchase_credit_note_id}"
        ),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check unavailable documents remain hidden
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_credit_note_document_success() {
    // Setup an authenticated credit-note request
    let event_purchase_credit_note_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);

    // Return the current account-scoped provider URL
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_get_purchase_document_url()
        .times(1)
        .withf(move |uid, purchase_id, credit_note_id| {
            *uid == ids.user_id
                && *purchase_id == event_purchase_id
                && *credit_note_id == Some(event_purchase_credit_note_id)
        })
        .returning(|_, _, _| {
            Box::pin(async { Ok(Some("https://payments.test/credit-note".to_string())) })
        });

    // Request the credit-note document
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = get_request(
        &format!(
            "/dashboard/user/purchases/{event_purchase_id}/credit-notes/{event_purchase_credit_note_id}"
        ),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

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
async fn test_invoice_document_returns_manager_rejection() {
    // Setup an authenticated invoice request
    let event_purchase_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);

    // Reject the document lookup with a user-facing message
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_get_purchase_document_url()
        .times(1)
        .returning(|_, _, _| {
            Box::pin(async {
                Err(HandlerError::Database("invoice is not issued yet".to_string()).into())
            })
        });

    // Request the invoice document
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = get_request(
        &format!("/dashboard/user/purchases/{event_purchase_id}/invoice"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the rejection message is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), b"invoice is not issued yet");
}

#[tokio::test]
async fn test_invoice_document_success() {
    // Setup an authenticated invoice request
    let event_purchase_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);

    // Return the current account-scoped provider URL
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_get_purchase_document_url()
        .times(1)
        .withf(move |uid, purchase_id, credit_note_id| {
            *uid == ids.user_id && *purchase_id == event_purchase_id && credit_note_id.is_none()
        })
        .returning(|_, _, _| {
            Box::pin(async { Ok(Some("https://payments.test/invoice".to_string())) })
        });

    // Request the invoice document
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let request = get_request(
        &format!("/dashboard/user/purchases/{event_purchase_id}/invoice"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the attendee is redirected to the fresh provider document
    assert_empty_response(&parts, &bytes, StatusCode::TEMPORARY_REDIRECT);
    assert_eq!(
        parts.headers.get(LOCATION),
        Some(&HeaderValue::from_static("https://payments.test/invoice")),
    );
}

#[tokio::test]
async fn test_list_page_success() {
    // Setup an authenticated paginated list request
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_list_user_purchase_documents()
        .times(1)
        .withf(move |uid, filters| {
            *uid == ids.user_id && filters.limit == Some(5) && filters.offset == Some(10)
        })
        .returning(|_, _| {
            Ok(PurchaseDocumentsOutput {
                purchases: Vec::new(),
                total: 0,
            })
        });

    // Request the purchase-document partial with pagination
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request(
        "/dashboard/user/purchases?limit=5&offset=10",
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the partial and browser navigation URL
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_eq!(
        parts.headers.get("hx-push-url"),
        Some(&HeaderValue::from_static(
            "/dashboard/user?tab=purchases&limit=5&offset=10"
        )),
    );
    let body = std::str::from_utf8(&bytes).unwrap();
    assert!(body.contains("No paid-ticket documents yet"));
}
