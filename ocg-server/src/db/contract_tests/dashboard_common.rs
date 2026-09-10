//! Contract tests for the `DBDashboardCommon` functions.

use anyhow::Result;

use crate::db::dashboard::common::DBDashboardCommon;

use super::helpers::{
    attendee_id, community_id, contract_tests_db, group_id, organizer_id, subgroup_id,
};

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_group_parent_options_deserializes() -> Result<()> {
    // Setup the contract database and subgroup context
    let db = contract_tests_db()?;

    // Load selectable parent options through the Rust contract
    let options = db
        .list_group_parent_options(community_id(), organizer_id(), Some(subgroup_id()))
        .await?;

    // Select the seeded parent option
    let parent = options
        .iter()
        .find(|option| option.group_id == group_id())
        .expect("contract group should be a parent option");

    // Check parent activity and selection fields
    assert!(parent.active);
    assert_eq!(parent.name, "Contract Group");
    assert!(!parent.is_current);
    assert!(parent.is_selectable);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_search_user_deserializes() -> Result<()> {
    // Setup the contract database and user query
    let db = contract_tests_db()?;

    // Search users through the Rust contract
    let users = db.search_user("contract-att").await?;

    // Check the matching public user fields
    assert_eq!(users.len(), 1);
    assert_eq!(users[0].user_id, attendee_id());
    assert_eq!(users[0].username, "contract-attendee");
    assert_eq!(users[0].name.as_deref(), Some("Contract Attendee"));

    Ok(())
}
