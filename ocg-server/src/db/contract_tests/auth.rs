//! Contract tests for the `DBAuth` functions.

use anyhow::Result;

use crate::{auth::ExternalUserProfile, db::auth::DBAuth, types::user::UserProvider};

use super::helpers::{
    activation_id, attendee_id, contract_tests_db, external_lookup_id, external_update_id,
    organizer_id, pre_registered_id,
};

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_activate_pre_registered_user_external_provider_deserializes() -> Result<()> {
    // Setup the activation identity and external profile
    let db = contract_tests_db()?;
    let profile = ExternalUserProfile {
        email: "activation.contract@example.com".to_string(),
        name: "Contract Activation".to_string(),
        username: "contract-activation".to_string(),

        has_password: None,
        password: None,
        provider: Some(UserProvider::from_github_username(
            "contract-activation".to_string(),
        )),
    };

    // Activate the pre-registered user through the Rust contract
    let user = db
        .activate_pre_registered_user_external_provider(&activation_id(), &profile)
        .await?;

    // Check the registered external user fields
    assert!(user.email_verified);
    assert_eq!(user.name, "Contract Activation");
    assert_eq!(user.registration_status, "registered");
    assert_eq!(user.user_id, activation_id());
    assert_eq!(user.username, "contract-activation");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_user_by_email_for_external_auth_pre_registered_deserializes() -> Result<()>
{
    // Setup the contract database and normalized email lookup
    let db = contract_tests_db()?;

    // Load the pre-registered user through the auth contract
    let user = db
        .get_user_by_email_for_external_auth("PRE-REGISTERED.CONTRACT@example.com")
        .await?
        .expect("contract pre-registered user should exist");

    // Check pre-registration identity fields
    assert_eq!(user.user_id, pre_registered_id());
    assert_eq!(user.name, "");
    assert_eq!(user.registration_status, "pre-registered");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_user_by_id_deserializes() -> Result<()> {
    // Setup the contract database and user identifier
    let db = contract_tests_db()?;

    // Load the user by identifier through the Rust contract
    let user = db
        .get_user_by_id(&attendee_id())
        .await?
        .expect("contract attendee should exist");

    // Check account and provider profile fields
    assert!(user.email_verified);
    assert_eq!(user.email, "attendee.contract@example.com");
    assert_eq!(
        user.github_url.as_deref(),
        Some("https://github.com/contract-attendee")
    );
    assert_eq!(user.user_id, attendee_id());
    assert_eq!(user.username, "contract-attendee");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_user_by_linuxfoundation_identity_for_external_auth_deserializes()
-> Result<()> {
    // Setup the contract database and provider identity
    let db = contract_tests_db()?;

    // Load the user through the Linux Foundation auth contract
    let user = db
        .get_user_by_linuxfoundation_identity_for_external_auth(
            "https://issuer.example.com",
            "auth0|contract-external-lookup",
        )
        .await?
        .expect("contract LF provider user should exist");

    // Check external account identity fields
    assert_eq!(user.email, "external-lookup.contract@example.com");
    assert_eq!(user.name, "");
    assert_eq!(user.user_id, external_lookup_id());
    assert_eq!(user.username, "contract-external-lookup");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_user_by_username_deserializes() -> Result<()> {
    // Setup the contract database and username lookup
    let db = contract_tests_db()?;

    // Load the user by username through the Rust contract
    let user = db
        .get_user_by_username("contract-organizer")
        .await?
        .expect("contract organizer should exist");

    // Check public user identity fields
    assert_eq!(user.name, "Contract Organizer");
    assert_eq!(user.user_id, organizer_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_update_user_external_auth_deserializes() -> Result<()> {
    // Setup the contract database and external profile update
    let db = contract_tests_db()?;
    let profile = ExternalUserProfile {
        email: "external-update-new.contract@example.com".to_string(),
        name: "Contract External Update".to_string(),
        username: "contract-external-update".to_string(),

        has_password: None,
        password: None,
        provider: Some(UserProvider::from_linuxfoundation_identity(
            "https://issuer.example.com".to_string(),
            "auth0|contract-external-update".to_string(),
            "contract-external-update".to_string(),
        )),
    };

    // Update external authentication through the Rust contract
    let user = db.update_user_external_auth(&external_update_id(), &profile).await?;

    // Check account identity and verification fields
    assert_eq!(user.email, "external-update-new.contract@example.com");
    assert!(user.email_verified);
    assert_eq!(user.name, "Contract External Update");
    assert_eq!(user.user_id, external_update_id());

    // Check provider identities deserialize as expected
    assert_eq!(
        user.provider,
        Some(UserProvider {
            github: Some(crate::types::user::GitHubUserProvider {
                username: "contract-external-update".to_string(),
            }),
            linuxfoundation: Some(crate::types::user::LinuxFoundationUserProvider {
                username: "contract-external-update".to_string(),

                issuer: Some("https://issuer.example.com".to_string()),
                subject: Some("auth0|contract-external-update".to_string()),
            }),
        })
    );

    Ok(())
}
