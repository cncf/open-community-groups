//! Contract tests for the `DBAuth` functions.

use std::collections::HashMap;

use anyhow::Result;
use axum_login::tower_sessions::session;
use serde_json::json;
use time::{Duration, OffsetDateTime};
use tokio_postgres::types::Json;

use crate::{auth::ExternalUserProfile, db::auth::DBAuth, types::user::UserProvider};

use super::helpers::*;

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
async fn db_contracts_get_session_ignores_expired_sessions() -> Result<()> {
    // Setup a session that expired well before the database clock
    let db = contract_tests_db()?;
    let expired = session::Record {
        data: HashMap::from([("state".to_string(), json!("expired"))]),
        expiry_date: OffsetDateTime::now_utc() - Duration::hours(1),
        id: session::Id::default(),
    };
    db.create_session(&expired).await?;

    // Load the expired and a missing session through the Rust contract
    let expired_session = db.get_session(&expired.id).await?;
    let missing_session = db.get_session(&session::Id::default()).await?;

    // Check neither session is returned
    assert!(expired_session.is_none());
    assert!(missing_session.is_none());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_session_round_trips_unexpired_sessions() -> Result<()> {
    // Setup a session that expires well after the database clock
    let db = contract_tests_db()?;
    let record = session::Record {
        data: HashMap::from([("state".to_string(), json!("unexpired"))]),
        expiry_date: OffsetDateTime::now_utc() + Duration::hours(1),
        id: session::Id::default(),
    };
    db.create_session(&record).await?;

    // Load the session through the Rust contract
    let session = db
        .get_session(&record.id)
        .await?
        .expect("unexpired contract session should exist");

    // Check the stored session fields
    assert_eq!(session.data, record.data);
    assert_eq!(
        session.expiry_date.unix_timestamp(),
        record.expiry_date.unix_timestamp()
    );
    assert_eq!(session.id, record.id);

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
    // Setup the contract database, raw JSON probe, and user identifier
    let db = contract_tests_db()?;
    let client = contract_tests_pool()?.get().await?;

    // Load the user by identifier through the Rust contract
    let user = db
        .get_user_by_id(&attendee_id())
        .await?
        .expect("contract attendee should exist");
    let raw_row = client
        .query_one("select get_user_by_id($1::uuid, true)", &[&attendee_id()])
        .await?;
    let Json(raw): Json<serde_json::Value> = raw_row.get(0);

    // Check account and provider profile fields
    assert!(user.email_verified);
    assert_eq!(user.email, "attendee.contract@example.com");
    assert_eq!(
        user.github_url.as_deref(),
        Some("https://github.com/contract-attendee")
    );
    assert_eq!(user.user_id, attendee_id());
    assert_eq!(user.username, "contract-attendee");
    assert!(
        !raw.as_object()
            .unwrap()
            .contains_key("optional_notifications_enabled")
    );

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
