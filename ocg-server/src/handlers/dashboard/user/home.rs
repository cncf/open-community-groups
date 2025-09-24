//! HTTP handlers for the user dashboard.

use std::collections::HashMap;

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Query, State},
    response::{Html, IntoResponse},
};
use axum_messages::Messages;
use tracing::instrument;

use crate::{
    auth::AuthSession,
    db::DynDB,
    handlers::{error::HandlerError, extractors::CommunityId},
    templates::{
        PageId,
        auth::{self, User, UserDetails},
        dashboard::user::home::{Content, Page, Tab},
        dashboard::user::invitations,
    },
};

/// Handler that returns the user dashboard home page.
///
/// This handler manages the main user dashboard page, selecting the appropriate tab
/// and preparing the content for each dashboard section.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    auth_session: AuthSession,
    messages: Messages,
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
    Query(query): Query<HashMap<String, String>>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.as_ref().expect("user to be logged in").clone();

    // Get selected tab from query
    let tab: Tab = query.get("tab").unwrap_or(&String::new()).parse().unwrap_or_default();

    // Get community information
    let community = db.get_community(community_id).await?;

    // Prepare content for the selected tab
    let content = match tab {
        Tab::Account => {
            let timezones = db.list_timezones().await?;
            Content::Account(Box::new(auth::UpdateUserPage {
                has_password: user.has_password.unwrap_or(false),
                timezones,
                user: UserDetails::from(user),
            }))
        }
        Tab::Invitations => {
            let (community_invitations, group_invitations) = tokio::try_join!(
                db.list_user_community_team_invitations(community_id, user.user_id),
                db.list_user_group_team_invitations(community_id, user.user_id)
            )?;
            Content::Invitations(invitations::ListPage {
                community_invitations,
                group_invitations,
            })
        }
    };

    // Render the page
    let page = Page {
        community,
        content,
        messages: messages.into_iter().collect(),
        page_id: PageId::UserDashboard,
        path: "/dashboard/user".to_string(),
        user: User::from_session(auth_session).await?,
    };

    let html = Html(page.render()?);
    Ok(html)
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
    use serde_json::json;
    use time::{Duration as TimeDuration, OffsetDateTime};
    use tower::ServiceExt;
    use uuid::Uuid;

    use crate::{
        auth::User as AuthUser,
        db::mock::MockDB,
        router::setup_test_router,
        services::notifications::MockNotificationsManager,
        templates::dashboard::user::invitations::{CommunityTeamInvitation, GroupTeamInvitation},
        types::{
            community::{Community, Theme},
            group::GroupRole,
        },
    };

    #[tokio::test]
    async fn test_page_account_tab_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_community()
            .times(1)
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(sample_community(community_id)));
        db.expect_list_timezones()
            .times(1)
            .returning(|| Ok(vec!["UTC".to_string(), "America/New_York".to_string()]));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/user")
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
    async fn test_page_invitations_tab_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash);
        let community_invitations = vec![sample_community_invitation()];
        let group_invitations = vec![sample_group_invitation(group_id)];

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_community()
            .times(1)
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(sample_community(community_id)));
        db.expect_list_user_community_team_invitations()
            .times(1)
            .withf(move |id, uid| *id == community_id && *uid == user_id)
            .returning(move |_, _| Ok(community_invitations.clone()));
        db.expect_list_user_group_team_invitations()
            .times(1)
            .withf(move |id, uid| *id == community_id && *uid == user_id)
            .returning(move |_, _| Ok(group_invitations.clone()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/user?tab=invitations")
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
    async fn test_page_db_error() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        let auth_hash_for_user = auth_hash.clone();
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash_for_user))));
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_community()
            .times(1)
            .withf(move |id| *id == community_id)
            .returning(move |_| Err(anyhow!("db error")));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/user")
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

            has_password: Some(true),
            ..Default::default()
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
            theme: Theme {
                palette: BTreeMap::new(),
                primary_color: "#000000".to_string(),
            },
            title: "Test Community".to_string(),
            ..Default::default()
        }
    }

    /// Helper to create a sample community team invitation for tests.
    fn sample_community_invitation() -> CommunityTeamInvitation {
        CommunityTeamInvitation {
            community_name: "test-community".to_string(),
            created_at: Utc.with_ymd_and_hms(2024, 1, 1, 0, 0, 0).unwrap(),
        }
    }

    /// Helper to create a sample group team invitation for tests.
    fn sample_group_invitation(group_id: Uuid) -> GroupTeamInvitation {
        GroupTeamInvitation {
            created_at: Utc.with_ymd_and_hms(2024, 1, 2, 0, 0, 0).unwrap(),
            group_id,
            group_name: "Test Group".to_string(),
            role: GroupRole::Organizer,
        }
    }

    /// Helper to create a sample session record for tests.
    fn sample_session_record(session_id: session::Id, user_id: Uuid, auth_hash: &str) -> session::Record {
        let mut data = HashMap::new();
        data.insert(
            "axum-login.data".to_string(),
            json!({
                "user_id": user_id,
                "auth_hash": auth_hash.as_bytes(),
            }),
        );
        session::Record {
            data,
            expiry_date: OffsetDateTime::now_utc().saturating_add(TimeDuration::days(1)),
            id: session_id,
        }
    }
}
