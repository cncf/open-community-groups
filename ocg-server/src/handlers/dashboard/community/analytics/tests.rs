use axum::http::StatusCode;

use crate::{db::mock::MockDB, handlers::tests::*, types::permissions::CommunityPermission};

#[tokio::test]
async fn test_page_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let stats = sample_community_stats();

    // Setup database mock
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::Read);
    db.expect_get_community_stats()
        .times(1)
        .withf(move |community_id| *community_id == ids.community_id)
        .returning(move |_| Ok(stats.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/community/analytics", ids.session_id);
    let (parts, bytes) = send(router, request).await;
    let html = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the analytics page is rendered
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(html.contains(r#"data-analytics-tab="groups""#));
}
