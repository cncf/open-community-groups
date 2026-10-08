//! Contract tests for the `DBDashboardCommunity` functions.

use anyhow::Result;

use crate::{
    db::dashboard::community::DBDashboardCommunity,
    types::{
        community::CommunityRole,
        dashboard::{
            common::AuditLogFilters,
            community::{
                contact::{CommunityContactFilters, RegionFilterValue},
                team::CommunityTeamFilters,
            },
        },
        group::GroupRole,
    },
};

use super::helpers::*;

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_community_contact_recipients_summary_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Summarize every qualifying contact seat through the Rust contract
    let summary = db
        .get_community_contact_recipients_summary(
            contact_community_id(),
            &CommunityContactFilters::default(),
        )
        .await?;

    // Check distinct people, seats and contributing groups
    assert_eq!(summary.groups.len(), 2);
    assert_eq!(summary.groups[0].group_category_name, "Contact Category A");
    assert_eq!(summary.groups[0].group_id, contact_group_a_id());
    assert_eq!(summary.groups[0].name, "Contact Group A");
    assert_eq!(summary.groups[0].seats_count, 2);
    assert_eq!(
        summary.groups[0].region_name.as_deref(),
        Some("Contact Region")
    );
    assert_eq!(summary.groups[1].group_category_name, "Contact Category B");
    assert_eq!(summary.groups[1].name, "Contact Group B");
    assert_eq!(summary.groups[1].seats_count, 1);
    assert_eq!(summary.groups[1].region_name, None);
    assert_eq!(summary.groups_count, 2);
    assert_eq!(summary.people_count, 2);
    assert_eq!(summary.seats_count, 3);

    // Summarize the seats matching every filter together
    let filtered = db
        .get_community_contact_recipients_summary(
            contact_community_id(),
            &CommunityContactFilters {
                group_category_ids: vec![contact_category_b_id()],
                regions: vec![RegionFilterValue::NoRegion],
                roles: vec![GroupRole::Viewer],
            },
        )
        .await?;

    // Check only the viewer seat in the group without a region matches
    assert_eq!(filtered.groups_count, 1);
    assert_eq!(filtered.people_count, 1);
    assert_eq!(filtered.seats_count, 1);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_community_contact_recipients_summary_rejects_foreign_filters()
-> Result<()> {
    // Setup the contract database and a category of another community
    let db = contract_tests_db()?;
    let filters = CommunityContactFilters {
        group_category_ids: vec![group_category_id()],
        ..Default::default()
    };

    // Summarize recipients with the foreign category
    let err = db
        .get_community_contact_recipients_summary(contact_community_id(), &filters)
        .await
        .expect_err("foreign category should be rejected");

    // Check the user-facing rejection is raised
    assert_eq!(
        ocg01_message(&err).as_deref(),
        Some("group category not found")
    );

    Ok(())
}

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
async fn db_contracts_list_community_contact_filter_options_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load the contact filter options through the Rust contract
    let options = db
        .list_community_contact_filter_options(contact_community_id())
        .await?;

    // Check categories, regions and the no region count cover active groups only
    assert_eq!(options.group_categories.len(), 2);
    assert_eq!(
        options.group_categories[0].group_category_id,
        contact_category_a_id()
    );
    assert_eq!(options.group_categories[0].groups_count, 1);
    assert_eq!(options.group_categories[0].name, "Contact Category A");
    assert_eq!(options.group_categories[1].groups_count, 1);
    assert_eq!(options.no_region_groups_count, 1);
    assert_eq!(options.regions.len(), 1);
    assert_eq!(options.regions[0].groups_count, 1);
    assert_eq!(options.regions[0].name, "Contact Region");
    assert_eq!(options.regions[0].region_id, contact_region_id());

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
