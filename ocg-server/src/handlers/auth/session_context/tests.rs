use std::sync::Arc;

use tower_sessions::{MemoryStore, Session};
use uuid::Uuid;

use crate::{
    db::{DynDB, mock::MockDB},
    handlers::tests::*,
};

use super::*;

#[tokio::test]
async fn test_resolve_community_dashboard_context_skips_unreadable_candidate() {
    // Setup identifiers and candidate communities
    let accessible_community_id = Uuid::new_v4();
    let inaccessible_candidate_id = Uuid::new_v4();
    let selected_community_id = Uuid::new_v4();
    let stale_group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let communities = vec![
        sample_community_summary(inaccessible_candidate_id),
        sample_community_summary(accessible_community_id),
    ];

    // Setup permission and selection database expectations
    let mut db = MockDB::new();
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == selected_community_id
                && *uid == user_id
                && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Ok(false));
    db.expect_list_user_communities()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| Ok(communities.clone()));
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == inaccessible_candidate_id
                && *uid == user_id
                && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Ok(false));
    db.expect_user_has_community_permission()
        .times(1)
        .withf(move |cid, uid, permission| {
            *cid == accessible_community_id
                && *uid == user_id
                && permission == CommunityPermission::Read
        })
        .returning(|_, _, _| Ok(true));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(|_| Ok(vec![]));

    // Setup stale in-memory dashboard context
    let db: DynDB = Arc::new(db);
    let session = session_with_selection(Some(selected_community_id), Some(stale_group_id)).await;

    // Resolve the first verified community context
    let resolved =
        resolve_community_dashboard_context(&db, &session, &user_id, CommunityPermission::Read)
            .await
            .expect("community context should resolve");

    // Check only the readable candidate is persisted
    assert_eq!(
        resolved,
        Some(ResolvedCommunityContext {
            community_id: accessible_community_id,
            has_requested_permission: true,
        })
    );
    assert_eq!(
        selected_ids(&session).await,
        (Some(accessible_community_id), None)
    );
}

#[tokio::test]
async fn test_resolve_group_dashboard_context_prefers_selected_community() {
    // Setup a selected community whose group follows another community in the listing
    let listed_community_id = Uuid::new_v4();
    let listed_group_id = Uuid::new_v4();
    let selected_community_id = Uuid::new_v4();
    let selected_group_id = Uuid::new_v4();
    let stale_group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let mut groups = sample_user_groups_by_community(listed_community_id, listed_group_id);
    groups.extend(sample_user_groups_by_community(
        selected_community_id,
        selected_group_id,
    ));

    // Setup permission and selection database expectations
    let mut db = MockDB::new();
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == selected_community_id
                && *gid == stale_group_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| Ok(groups.clone()));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == selected_community_id
                && *gid == selected_group_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(true));

    // Setup stale in-memory dashboard context
    let db: DynDB = Arc::new(db);
    let session = session_with_selection(Some(selected_community_id), Some(stale_group_id)).await;

    // Resolve group context from the preferred community
    let resolved = resolve_group_dashboard_context(&db, &session, &user_id, GroupPermission::Read)
        .await
        .expect("group context should resolve");

    // Check the selected community wins over listing order
    assert_eq!(
        resolved,
        Some(ResolvedGroupContext {
            community_id: selected_community_id,
            group_id: selected_group_id,
            has_requested_permission: true,
        })
    );
    assert_eq!(
        selected_ids(&session).await,
        (Some(selected_community_id), Some(selected_group_id))
    );
}

#[tokio::test]
async fn test_resolve_group_dashboard_context_repairs_across_communities() {
    // Setup a selected community with no readable groups and a readable fallback
    let fallback_community_id = Uuid::new_v4();
    let fallback_group_id = Uuid::new_v4();
    let selected_community_id = Uuid::new_v4();
    let selected_group_id = Uuid::new_v4();
    let stale_group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let mut groups = sample_user_groups_by_community(fallback_community_id, fallback_group_id);
    groups.extend(sample_user_groups_by_community(
        selected_community_id,
        selected_group_id,
    ));

    // Setup permission and selection database expectations
    let mut db = MockDB::new();
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == selected_community_id
                && *gid == stale_group_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| Ok(groups.clone()));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == selected_community_id
                && *gid == selected_group_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == fallback_community_id
                && *gid == fallback_group_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(true));

    // Setup stale in-memory dashboard context
    let db: DynDB = Arc::new(db);
    let session = session_with_selection(Some(selected_community_id), Some(stale_group_id)).await;

    // Resolve group context from the fallback community
    let resolved = resolve_group_dashboard_context(&db, &session, &user_id, GroupPermission::Read)
        .await
        .expect("group context should resolve");

    // Check both selected identifiers move to the fallback context
    assert_eq!(
        resolved,
        Some(ResolvedGroupContext {
            community_id: fallback_community_id,
            group_id: fallback_group_id,
            has_requested_permission: true,
        })
    );
    assert_eq!(
        selected_ids(&session).await,
        (Some(fallback_community_id), Some(fallback_group_id))
    );
}

#[tokio::test]
async fn test_resolve_group_dashboard_context_skips_unreadable_candidate() {
    // Setup identifiers and candidate groups
    let accessible_group_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let inaccessible_candidate_id = Uuid::new_v4();
    let selected_group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let mut groups = sample_user_groups_by_community(community_id, inaccessible_candidate_id);
    groups[0].groups.push(sample_group_minimal(accessible_group_id));

    // Setup permission and selection database expectations
    let mut db = MockDB::new();
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == selected_group_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| Ok(groups.clone()));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == inaccessible_candidate_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == accessible_group_id
                && *uid == user_id
                && permission == GroupPermission::Read
        })
        .returning(|_, _, _, _| Ok(true));

    // Setup stale in-memory dashboard context
    let db: DynDB = Arc::new(db);
    let session = session_with_selection(Some(community_id), Some(selected_group_id)).await;

    // Resolve the first verified group context
    let resolved = resolve_group_dashboard_context(&db, &session, &user_id, GroupPermission::Read)
        .await
        .expect("group context should resolve");

    // Check only the readable candidate is persisted
    assert_eq!(
        resolved,
        Some(ResolvedGroupContext {
            community_id,
            group_id: accessible_group_id,
            has_requested_permission: true,
        })
    );
    assert_eq!(
        selected_ids(&session).await,
        (Some(community_id), Some(accessible_group_id))
    );
}

#[tokio::test]
async fn test_select_first_community_and_group_selects_community_when_user_has_no_groups() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(|_| Ok(vec![]));
    db.expect_list_user_communities()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| Ok(vec![sample_community_summary(community_id)]));

    // Setup in-memory session
    let db: DynDB = Arc::new(db);
    let session = session_with_selection(None, None).await;

    // Execute helper
    select_first_community_and_group(&db, &session, &user_id)
        .await
        .expect("helper should select first available community");

    // Check session data matches expectations
    assert_eq!(selected_ids(&session).await, (Some(community_id), None));
}

// Helpers.

/// Builds an in-memory session selecting the given community and group.
async fn session_with_selection(community_id: Option<Uuid>, group_id: Option<Uuid>) -> Session {
    let session = Session::new(None, Arc::new(MemoryStore::default()), None);
    if let Some(community_id) = community_id {
        session.insert(SELECTED_COMMUNITY_ID_KEY, community_id).await.unwrap();
    }
    if let Some(group_id) = group_id {
        session.insert(SELECTED_GROUP_ID_KEY, group_id).await.unwrap();
    }
    session
}
