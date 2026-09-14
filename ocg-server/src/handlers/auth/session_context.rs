//! This module manages the dashboard context stored in the session: the
//! selected community and group, how they are resolved and repaired when
//! stale, and how they are synchronized after a selection change.

use tower_sessions::Session;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::error::HandlerError,
    types::permissions::{CommunityPermission, GroupPermission},
};

#[cfg(test)]
mod tests;

/// Key used to store the selected community ID in the session.
pub(crate) const SELECTED_COMMUNITY_ID_KEY: &str = "selected_community_id";

/// Key used to store the selected group ID in the session.
pub(crate) const SELECTED_GROUP_ID_KEY: &str = "selected_group_id";

/// Defines whether syncing a community selection requires a group selection.
pub(crate) enum SelectedGroupPolicy {
    /// Group selection may be absent.
    Optional,
    /// Group selection must be present.
    Required,
}

/// Resolves community dashboard context and repairs stale selection.
pub(super) async fn resolve_community_dashboard_context(
    db: &DynDB,
    session: &Session,
    user_id: &Uuid,
    permission: CommunityPermission,
) -> Result<Option<Uuid>, HandlerError> {
    // Preserve the existing fast path for valid selected context
    let selected_community_id = session.get::<Uuid>(SELECTED_COMMUNITY_ID_KEY).await?;
    if let Some(community_id) = selected_community_id {
        let has_permission = db
            .user_has_community_permission(&community_id, user_id, permission)
            .await?;
        if has_permission {
            return Ok(Some(community_id));
        }

        // Missing write permission is a normal denial while base access remains valid
        if permission != CommunityPermission::Read {
            let has_read_permission = db
                .user_has_community_permission(&community_id, user_id, CommunityPermission::Read)
                .await?;
            if has_read_permission {
                return Err(HandlerError::Forbidden);
            }
        }
    }

    // Repair missing or unreadable context before applying stronger permissions
    let repaired_community_id = repair_community_dashboard_context(db, session, user_id).await?;
    if let Some(community_id) = repaired_community_id
        && permission != CommunityPermission::Read
    {
        let has_permission = db
            .user_has_community_permission(&community_id, user_id, permission)
            .await?;
        if !has_permission {
            return Err(HandlerError::Forbidden);
        }
    }

    Ok(repaired_community_id)
}

/// Resolves group dashboard context and repairs stale selection.
pub(super) async fn resolve_group_dashboard_context(
    db: &DynDB,
    session: &Session,
    user_id: &Uuid,
    permission: GroupPermission,
) -> Result<Option<(Uuid, Uuid)>, HandlerError> {
    // Preserve the existing fast path for valid selected context
    let selected_community_id = session.get::<Uuid>(SELECTED_COMMUNITY_ID_KEY).await?;
    let selected_group_id = session.get::<Uuid>(SELECTED_GROUP_ID_KEY).await?;
    if let (Some(community_id), Some(group_id)) = (selected_community_id, selected_group_id) {
        let has_permission = db
            .user_has_group_permission(&community_id, &group_id, user_id, permission)
            .await?;
        if has_permission {
            return Ok(Some((community_id, group_id)));
        }

        // Missing write permission is a normal denial while base access remains valid
        if permission != GroupPermission::Read {
            let has_read_permission = db
                .user_has_group_permission(&community_id, &group_id, user_id, GroupPermission::Read)
                .await?;
            if has_read_permission {
                return Err(HandlerError::Forbidden);
            }
        }
    }

    // Repair missing or unreadable context before applying stronger permissions
    let repaired_ids = repair_group_dashboard_context(
        db,
        session,
        user_id,
        selected_community_id,
        selected_group_id.is_some(),
    )
    .await?;
    if let Some((community_id, group_id)) = repaired_ids
        && permission != GroupPermission::Read
    {
        let has_permission = db
            .user_has_group_permission(&community_id, &group_id, user_id, permission)
            .await?;
        if !has_permission {
            return Err(HandlerError::Forbidden);
        }
    }

    Ok(repaired_ids)
}

/// Selects the first available community and group for the user in the session.
pub(crate) async fn select_first_community_and_group(
    db: &DynDB,
    session: &Session,
    user_id: &Uuid,
) -> Result<(), HandlerError> {
    let groups_by_community = db.list_user_groups(user_id).await?;
    if let Some(first_community) = groups_by_community.first() {
        session
            .insert(
                SELECTED_COMMUNITY_ID_KEY,
                first_community.community.community_id,
            )
            .await?;
        if let Some(first_group) = first_community.groups.first() {
            session.insert(SELECTED_GROUP_ID_KEY, first_group.group_id).await?;
        }
    } else {
        // User might be a community team member without groups
        let communities = db.list_user_communities(user_id).await?;
        if let Some(first_community) = communities.first() {
            session
                .insert(SELECTED_COMMUNITY_ID_KEY, first_community.community_id)
                .await?;
        }
    }
    Ok(())
}

/// Syncs the selected community and first available group in the session.
pub(crate) async fn sync_selected_community_and_group(
    db: &DynDB,
    session: &Session,
    user_id: &Uuid,
    community_id: Uuid,
    selected_group_policy: SelectedGroupPolicy,
) -> Result<(), HandlerError> {
    // Load the user's groups to keep the selected group in sync
    let groups_by_community = db.list_user_groups(user_id).await?;
    let first_group_id = groups_by_community
        .iter()
        .find(|c| c.community.community_id == community_id)
        .and_then(|c| c.groups.first())
        .map(|g| g.group_id);

    if matches!(selected_group_policy, SelectedGroupPolicy::Required) && first_group_id.is_none() {
        return Err(HandlerError::Forbidden);
    }

    // Persist the community selection and align the group selection with it
    session.insert(SELECTED_COMMUNITY_ID_KEY, community_id).await?;
    if let Some(first_group_id) = first_group_id {
        session.insert(SELECTED_GROUP_ID_KEY, first_group_id).await?;
    } else {
        session.remove::<Uuid>(SELECTED_GROUP_ID_KEY).await?;
    }

    Ok(())
}

/// Repairs community dashboard context using the first readable candidate.
async fn repair_community_dashboard_context(
    db: &DynDB,
    session: &Session,
    user_id: &Uuid,
) -> Result<Option<Uuid>, HandlerError> {
    // Find the first listed community that still grants dashboard access
    let communities = db.list_user_communities(user_id).await?;
    for community in communities {
        let has_read_permission = db
            .user_has_community_permission(
                &community.community_id,
                user_id,
                CommunityPermission::Read,
            )
            .await?;
        if !has_read_permission {
            continue;
        }

        // Persist only verified replacement context
        sync_selected_community_and_group(
            db,
            session,
            user_id,
            community.community_id,
            SelectedGroupPolicy::Optional,
        )
        .await?;
        return Ok(Some(community.community_id));
    }

    Ok(None)
}

/// Repairs group dashboard context using the first readable candidate.
async fn repair_group_dashboard_context(
    db: &DynDB,
    session: &Session,
    user_id: &Uuid,
    selected_community_id: Option<Uuid>,
    had_selected_group: bool,
) -> Result<Option<(Uuid, Uuid)>, HandlerError> {
    // Search the selected community before other listed group contexts
    let groups_by_community = db.list_user_groups(user_id).await?;
    let preferred_communities = groups_by_community
        .iter()
        .filter(|groups| Some(groups.community.community_id) == selected_community_id)
        .chain(
            groups_by_community
                .iter()
                .filter(|groups| Some(groups.community.community_id) != selected_community_id),
        );
    for groups in preferred_communities {
        for group in &groups.groups {
            let community_id = groups.community.community_id;
            let has_read_permission = db
                .user_has_group_permission(
                    &community_id,
                    &group.group_id,
                    user_id,
                    GroupPermission::Read,
                )
                .await?;
            if !has_read_permission {
                continue;
            }

            // Persist only verified replacement context
            session.insert(SELECTED_COMMUNITY_ID_KEY, community_id).await?;
            session.insert(SELECTED_GROUP_ID_KEY, group.group_id).await?;
            return Ok(Some((community_id, group.group_id)));
        }
    }

    // Clear an unusable group without disturbing potentially valid community context
    if had_selected_group {
        session.remove::<Uuid>(SELECTED_GROUP_ID_KEY).await?;
    }

    Ok(None)
}
