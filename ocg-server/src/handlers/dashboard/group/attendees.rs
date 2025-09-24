//! HTTP handlers for the attendees section in the group dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Query, State},
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CommunityId, SelectedGroupId},
    },
    templates::dashboard::group::attendees,
};

// Pages handlers.

/// Displays the list of attendees for the selected event and filters.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CommunityId(community_id): CommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Query(filters): Query<attendees::AttendeesFilters>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let attendees = db.search_event_attendees(group_id, &filters).await?;
    let event = if let Some(event_id) = filters.event_id {
        Some(db.get_event_summary(community_id, group_id, event_id).await?)
    } else {
        None
    };
    let template = attendees::ListPage {
        attendees,
        group_id,
        event,
    };

    Ok(Html(template.render()?))
}

// Tests.

#[cfg(test)]
mod tests {
    use std::collections::{BTreeMap, HashMap};

    use anyhow::anyhow;
    use axum::{
        body::{Body, to_bytes},
        http::{
            HeaderValue, Request, StatusCode,
            header::{CACHE_CONTROL, CONTENT_TYPE, COOKIE, HOST},
        },
    };
    use axum_login::tower_sessions::session;
    use chrono::{TimeZone, Utc};
    use chrono_tz::UTC;
    use serde_json::json;
    use time::{Duration as TimeDuration, OffsetDateTime};
    use tower::ServiceExt;
    use uuid::Uuid;

    use crate::{
        auth::User as AuthUser,
        db::mock::MockDB,
        handlers::auth::SELECTED_GROUP_ID_KEY,
        router::setup_test_router,
        services::notifications::MockNotificationsManager,
        templates::dashboard::group::attendees::Attendee,
        types::{
            community::Community,
            event::{EventKind, EventSummary},
        },
    };

    #[tokio::test]
    async fn test_list_page_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, group_id, &auth_hash);
        let attendee = sample_attendee();
        let community = sample_community(community_id);
        let event = sample_event_summary(event_id, group_id);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_get_community_id()
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_community()
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(community.clone()));
        db.expect_search_event_attendees()
            .withf(move |id, filters| *id == group_id && filters.event_id == Some(event_id))
            .returning(move |_, _| Ok(vec![attendee.clone()]));
        db.expect_get_event_summary()
            .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
            .returning(move |_, _, _| Ok(event.clone()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri(format!("/dashboard/group/attendees?event_id={event_id}"))
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::OK);
        assert_eq!(
            parts.headers.get(CONTENT_TYPE).unwrap(),
            &HeaderValue::from_static("text/html; charset=utf-8"),
        );
        assert_eq!(
            parts.headers.get(CACHE_CONTROL).unwrap(),
            &HeaderValue::from_static("max-age=0"),
        );
        assert!(!bytes.is_empty());
    }

    #[tokio::test]
    async fn test_list_page_db_error() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, group_id, &auth_hash);
        let community = sample_community(community_id);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_get_community_id()
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_community()
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(community.clone()));
        db.expect_search_event_attendees()
            .withf(move |id, filters| *id == group_id && filters.event_id.is_none())
            .returning(move |_, _| Err(anyhow!("db error")));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/group/attendees")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
        assert!(bytes.is_empty());
    }

    // Helpers.

    /// Helper to create a sample authenticated user for tests.
    fn sample_auth_user(user_id: Uuid, auth_hash: &str) -> AuthUser {
        AuthUser {
            auth_hash: auth_hash.to_string(),
            email: "user@example.test".to_string(),
            email_verified: true,
            name: "Test User".to_string(),
            user_id,
            username: "test-user".to_string(),
            belongs_to_any_group_team: Some(true),
            ..Default::default()
        }
    }

    /// Helper to create a sample attendee for tests.
    fn sample_attendee() -> Attendee {
        Attendee {
            checked_in: true,
            created_at: Utc.with_ymd_and_hms(2024, 1, 1, 12, 0, 0).unwrap(),
            username: "attendee".to_string(),

            company: Some("Example".to_string()),
            name: Some("Event Attendee".to_string()),
            photo_url: Some("https://example.test/avatar.png".to_string()),
            title: Some("Engineer".to_string()),
        }
    }

    /// Helper to create a sample community for tests.
    fn sample_community(community_id: Uuid) -> Community {
        Community {
            active: true,
            community_id,
            community_site_layout_id: "default".to_string(),
            created_at: 0,
            description: "Test community".to_string(),
            display_name: "Test".to_string(),
            header_logo_url: "/static/images/placeholder_cncf.png".to_string(),
            host: "example.test".to_string(),
            name: "test".to_string(),
            theme: crate::types::community::Theme {
                palette: BTreeMap::default(),
                primary_color: "#000000".to_string(),
            },
            title: "Test Community".to_string(),
            ..Default::default()
        }
    }

    /// Helper to create a sample event summary for tests.
    fn sample_event_summary(event_id: Uuid, _group_id: Uuid) -> EventSummary {
        EventSummary {
            canceled: false,
            event_id,
            group_category_name: "Meetup".to_string(),
            group_color: "#123456".to_string(),
            group_name: "Test Group".to_string(),
            group_slug: "test-group".to_string(),
            kind: EventKind::Virtual,
            name: "Sample Event".to_string(),
            published: true,
            slug: "sample-event".to_string(),
            timezone: UTC,

            group_city: Some("Test City".to_string()),
            group_country_code: Some("US".to_string()),
            group_country_name: Some("United States".to_string()),
            group_state: Some("MA".to_string()),
            logo_url: Some("https://example.test/logo.png".to_string()),
            starts_at: Some(Utc.with_ymd_and_hms(2024, 2, 1, 18, 0, 0).unwrap()),
            venue_city: Some("Boston".to_string()),
        }
    }

    /// Helper to create a sample session record including the selected group ID.
    fn sample_session_record(
        session_id: session::Id,
        user_id: Uuid,
        group_id: Uuid,
        auth_hash: &str,
    ) -> session::Record {
        let mut data = HashMap::new();
        data.insert(
            "axum-login.data".to_string(),
            json!({
                "user_id": user_id,
                "auth_hash": auth_hash.as_bytes(),
            }),
        );
        data.insert(SELECTED_GROUP_ID_KEY.to_string(), json!(group_id));
        session::Record {
            data,
            expiry_date: OffsetDateTime::now_utc().saturating_add(TimeDuration::days(1)),
            id: session_id,
        }
    }
}
