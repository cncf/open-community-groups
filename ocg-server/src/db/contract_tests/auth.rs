//! Contract tests for the `DBAuth` functions.

use std::collections::HashMap;

use anyhow::Result;
use axum_login::tower_sessions::session;
use serde_json::json;
use time::{Duration, OffsetDateTime};
use tokio_postgres::types::Json;
use uuid::Uuid;

use crate::{
    auth::ExternalUserProfile,
    db::{
        DBUnitOfWork, PgExecutor,
        auth::{AUTH_CLEANUP_BATCH_SIZE, DBAuth, EmailVerificationNotification},
    },
    types::user::UserProvider,
};

use super::helpers::*;

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_activate_pre_registered_user_email_password_deserializes() -> Result<()> {
    // Setup a rolled-back unit of work, the password profile and verification
    let uow = contract_unit_of_work().await?;
    let profile = ExternalUserProfile {
        email: "activation-password.contract@example.com".to_string(),
        name: "Contract Password Activation".to_string(),
        username: "contract-password-activation".to_string(),

        has_password: None,
        password: Some("contract_password_hash".to_string()),
        provider: None,
    };
    let verification = EmailVerificationNotification {
        code: Uuid::new_v4(),
        template_data: json!({
            "link": "https://example.com/verify-email/contract-password-activation",
        }),
    };

    // Activate the pre-registered user through the Rust contract
    let (user, verification_code) = uow
        .activate_pre_registered_user_email_password(&profile, &verification)
        .await?
        .expect("contract password activation user should exist");

    // Check the activated user and verification code
    assert!(!user.email_verified);
    assert_eq!(user.name, "Contract Password Activation");
    assert_eq!(user.registration_status, "registered");
    assert_eq!(user.user_id, activation_password_id());
    assert_eq!(user.username, "contract-password-activation");
    assert_eq!(user.has_password, Some(true));
    assert_eq!(verification_code, verification.code);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_activate_pre_registered_user_external_provider_deserializes() -> Result<()> {
    // Setup a rolled-back unit of work, the activation identity and external profile
    let uow = contract_unit_of_work().await?;
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
    let user = uow
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
async fn db_contracts_delete_expired_auth_sessions_deletes_expired_and_skips_when_locked()
-> Result<()> {
    // Setup a rolled-back unit of work with two expired sessions and one active session
    let uow = contract_unit_of_work().await?;
    let now = OffsetDateTime::now_utc();
    let expired_oldest = session::Record {
        data: HashMap::from([("state".to_string(), json!("expired-oldest"))]),
        expiry_date: now - Duration::hours(2),
        id: session::Id::default(),
    };
    let expired_newer = session::Record {
        data: HashMap::from([("state".to_string(), json!("expired-newer"))]),
        expiry_date: now - Duration::hours(1),
        id: session::Id::default(),
    };
    let active = session::Record {
        data: HashMap::from([("state".to_string(), json!("active"))]),
        expiry_date: now + Duration::hours(1),
        id: session::Id::default(),
    };
    uow.create_session(&expired_oldest).await?;
    uow.create_session(&expired_newer).await?;
    uow.create_session(&active).await?;

    // Hold the cleanup advisory lock on a second connection and check cleanup skips cleanly
    let lock_uow = contract_unit_of_work().await?;
    lock_uow
        .execute(
            "select pg_advisory_xact_lock(hashtextextended('ocg:auth-session-cleanup', 0));",
            &[],
        )
        .await?;
    let skipped = uow.delete_expired_auth_sessions(AUTH_CLEANUP_BATCH_SIZE).await?;
    assert_eq!(skipped, 0);
    Box::new(lock_uow).rollback().await?;

    // Delete expired sessions in bounded batches after releasing the advisory lock
    let first_batch = uow.delete_expired_auth_sessions(1).await?;
    let second_batch = uow.delete_expired_auth_sessions(AUTH_CLEANUP_BATCH_SIZE).await?;
    let third_batch = uow.delete_expired_auth_sessions(AUTH_CLEANUP_BATCH_SIZE).await?;

    // Check only expired sessions were deleted and the active session remains
    assert_eq!(first_batch, 1);
    assert_eq!(second_batch, 1);
    assert_eq!(third_batch, 0);
    let expired_ids = vec![expired_oldest.id.to_string(), expired_newer.id.to_string()];
    let remaining_expired: i64 = uow
        .fetch_scalar_one(
            "select count(*) from auth_session where auth_session_id = any($1::text[]);",
            &[&expired_ids],
        )
        .await?;
    assert_eq!(remaining_expired, 0);
    assert!(uow.get_session(&active.id).await?.is_some());

    Box::new(uow).rollback().await?;

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_delete_expired_email_verification_codes_deletes_expired_and_skips_when_locked()
-> Result<()> {
    // Setup a rolled-back unit of work with two expired codes and one active code
    let uow = contract_unit_of_work().await?;
    let expired_code_1 = Uuid::new_v4();
    let expired_code_2 = Uuid::new_v4();
    let active_code = Uuid::new_v4();
    uow.execute(
        "
        insert into email_verification_code (email_verification_code_id, created_at, user_id)
        values
            ($1::uuid, current_timestamp - interval '48 hours', $4::uuid),
            ($2::uuid, current_timestamp - interval '25 hours', $5::uuid),
            ($3::uuid, current_timestamp - interval '1 hour', $6::uuid);
        ",
        &[
            &expired_code_1,
            &expired_code_2,
            &active_code,
            &attendee_id(),
            &organizer_id(),
            &activation_id(),
        ],
    )
    .await?;

    // Hold the cleanup advisory lock on a second connection and check cleanup skips cleanly
    let lock_uow = contract_unit_of_work().await?;
    lock_uow
        .execute(
            "select pg_advisory_xact_lock(hashtextextended('ocg:email-verification-code-cleanup', 0));",
            &[],
        )
        .await?;
    let skipped = uow
        .delete_expired_email_verification_codes(AUTH_CLEANUP_BATCH_SIZE)
        .await?;
    assert_eq!(skipped, 0);
    Box::new(lock_uow).rollback().await?;

    // Delete expired verification codes in bounded batches after releasing the advisory lock
    let first_batch = uow.delete_expired_email_verification_codes(1).await?;
    let second_batch = uow
        .delete_expired_email_verification_codes(AUTH_CLEANUP_BATCH_SIZE)
        .await?;
    let third_batch = uow
        .delete_expired_email_verification_codes(AUTH_CLEANUP_BATCH_SIZE)
        .await?;

    // Check only expired verification codes were deleted and the active code remains
    assert_eq!(first_batch, 1);
    assert_eq!(second_batch, 1);
    assert_eq!(third_batch, 0);
    let expired_codes = vec![expired_code_1, expired_code_2];
    let remaining_expired: i64 = uow
        .fetch_scalar_one(
            "select count(*) from email_verification_code where email_verification_code_id = any($1::uuid[]);",
            &[&expired_codes],
        )
        .await?;
    assert_eq!(remaining_expired, 0);
    let remaining_active: i64 = uow
        .fetch_scalar_one(
            "select count(*) from email_verification_code where email_verification_code_id = $1::uuid;",
            &[&active_code],
        )
        .await?;
    assert_eq!(remaining_active, 1);

    Box::new(uow).rollback().await?;

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_session_ignores_expired_sessions() -> Result<()> {
    // Setup a rolled-back unit of work and a session that expired well before the database clock
    let uow = contract_unit_of_work().await?;
    let expired = session::Record {
        data: HashMap::from([("state".to_string(), json!("expired"))]),
        expiry_date: OffsetDateTime::now_utc() - Duration::hours(1),
        id: session::Id::default(),
    };
    uow.create_session(&expired).await?;

    // Load the expired and a missing session through the Rust contract
    let expired_session = uow.get_session(&expired.id).await?;
    let missing_session = uow.get_session(&session::Id::default()).await?;

    // Check neither session is returned
    assert!(expired_session.is_none());
    assert!(missing_session.is_none());

    Box::new(uow).rollback().await?;

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_session_round_trips_unexpired_sessions() -> Result<()> {
    // Setup a rolled-back unit of work and a session that expires well after the database clock
    let uow = contract_unit_of_work().await?;
    let record = session::Record {
        data: HashMap::from([("state".to_string(), json!("unexpired"))]),
        expiry_date: OffsetDateTime::now_utc() + Duration::hours(1),
        id: session::Id::default(),
    };
    uow.create_session(&record).await?;

    // Load the session through the Rust contract
    let session = uow
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

    Box::new(uow).rollback().await?;

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
async fn db_contracts_sign_up_user_deserializes() -> Result<()> {
    // Setup a rolled-back unit of work and a verified sign-up profile without a password
    let uow = contract_unit_of_work().await?;
    let profile = ExternalUserProfile {
        email: "sign-up.contract@example.com".to_string(),
        name: "Contract Sign Up".to_string(),
        username: "contract-sign-up".to_string(),

        has_password: None,
        password: None,
        provider: None,
    };

    // Sign up the user through the Rust contract
    let (user, verification_code) = uow.sign_up_user(&profile, true, None).await?;

    // Check the signed up user fields and computed membership flags
    assert!(user.email_verified);
    assert_eq!(user.email, "sign-up.contract@example.com");
    assert_eq!(user.name, "Contract Sign Up");
    assert_eq!(user.registration_status, "registered");
    assert_eq!(user.username, "contract-sign-up");
    assert_eq!(user.has_password, None);
    assert_eq!(user.belongs_to_any_group_team, Some(false));
    assert_eq!(user.belongs_to_community_team, Some(false));
    assert!(verification_code.is_none());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_update_user_external_auth_deserializes() -> Result<()> {
    // Setup a rolled-back unit of work and the external profile update
    let uow = contract_unit_of_work().await?;
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
    let user = uow.update_user_external_auth(&external_update_id(), &profile).await?;

    // Check account identity and verification fields
    assert_eq!(user.email, "external-update-new.contract@example.com");
    assert!(user.email_verified);
    assert_eq!(user.name, "Contract External Update");
    assert_eq!(user.registration_status, "registered");
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
