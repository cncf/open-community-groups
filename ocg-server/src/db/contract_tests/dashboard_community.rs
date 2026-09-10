//! Contract tests for the `DBDashboardCommunity` functions.

use anyhow::Result;

use crate::{
    db::dashboard::community::DBDashboardCommunity,
    templates::dashboard::{audit::AuditLogFilters, community::team::CommunityTeamFilters},
    types::community::CommunityRole,
};

use super::helpers::{community_id, contract_tests_db, organizer_id, waitlist_id};

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_community_stats_deserializes() -> Result<()> {
    // Setup the contract database and community fixture
    let db = contract_tests_db()?;

    // Load dashboard community statistics through the Rust contract
    let stats = db.get_community_stats(community_id()).await?;

    // Check entity and page-view totals
    assert_eq!(stats.attendees.total, 1);
    assert_eq!(stats.events.total, 2);
    assert_eq!(stats.groups.total, 2);
    assert_eq!(stats.members.total, 1);
    assert_eq!(stats.page_views.community.total_views, 0);
    assert_eq!(stats.page_views.events.total_views, 2);
    assert_eq!(stats.page_views.groups.total_views, 3);
    assert_eq!(stats.page_views.total_views, 5);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_community_audit_logs_deserializes() -> Result<()> {
    // Setup the contract database and audit filters
    let db = contract_tests_db()?;
    let filters = AuditLogFilters {
        limit: Some(10),
        offset: Some(0),

        ..Default::default()
    };

    // Load community audit logs through the Rust contract
    let output = db.list_community_audit_logs(community_id(), &filters).await?;

    // Check pagination and audit actor fields
    assert_eq!(output.total, 1);
    assert_eq!(output.logs.len(), 1);
    assert_eq!(output.logs[0].action, "group_payment_recipient_updated");
    assert_eq!(
        output.logs[0].actor_username.as_deref(),
        Some("contract-organizer")
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_community_roles_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load community roles through the Rust contract
    let roles = db.list_community_roles().await?;

    // Check role ordering and display fields
    assert_eq!(roles.len(), 3);
    assert_eq!(roles[0].community_role_id, "admin");
    assert_eq!(roles[0].display_name, "Admin");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_community_team_members_deserializes() -> Result<()> {
    // Setup the contract database and team filters
    let db = contract_tests_db()?;
    let filters = CommunityTeamFilters {
        limit: Some(10),
        offset: Some(0),
    };

    // Load community team members through the Rust contract
    let output = db.list_community_team_members(community_id(), &filters).await?;

    // Check accepted and pending team member rows
    assert_eq!(output.total, 2);
    assert_eq!(output.members.len(), 2);
    assert!(output.members[0].accepted);
    assert_eq!(output.members[0].role, Some(CommunityRole::Admin));
    assert_eq!(output.members[0].user_id, organizer_id());
    assert!(!output.members[1].accepted);
    assert_eq!(output.members[1].user_id, waitlist_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_group_categories_deserializes() -> Result<()> {
    // Setup the contract database and community fixture
    let db = contract_tests_db()?;

    // Load group categories through the Rust contract
    let categories = db.list_group_categories(community_id()).await?;

    // Check the seeded category
    assert_eq!(categories.len(), 1);
    assert_eq!(categories[0].name, "Technology");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_regions_deserializes() -> Result<()> {
    // Setup the contract database and community fixture
    let db = contract_tests_db()?;

    // Load regions through the Rust contract
    let regions = db.list_regions(community_id()).await?;

    // Check the seeded region
    assert_eq!(regions.len(), 1);
    assert_eq!(regions[0].name, "North America");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_user_communities_deserializes() -> Result<()> {
    // Setup the contract database and user fixture
    let db = contract_tests_db()?;

    // Load the user's communities through the Rust contract
    let communities = db.list_user_communities(&organizer_id()).await?;

    // Check the seeded community membership
    assert_eq!(communities.len(), 1);
    assert_eq!(communities[0].community_id, community_id());

    Ok(())
}
