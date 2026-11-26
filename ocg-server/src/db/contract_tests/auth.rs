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
        auth::{
            AUTH_CLEANUP_BATCH_SIZE, DBAuth, EmailVerificationNotification,
            PasswordResetNotification,
        },
    },
    types::user::UserProvider,
    util::hash_password_reset_token,
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
async fn db_contracts_create_password_reset_token_enforces_eligibility_and_cooldown() -> Result<()>
{
    // Setup a rolled-back unit of work and an unverified registered password user
    let uow = contract_unit_of_work().await?;
    let unverified_user_id = Uuid::new_v4();
    uow.execute(
        r#"
        insert into "user" (
            user_id,
            auth_hash,
            email,
            email_verified,
            password,
            registration_status,
            username
        ) values (
            $1::uuid,
            'contract_unverified_hash',
            'unverified-reset.contract@example.com',
            false,
            'contract_password_hash',
            'registered',
            'contract-unverified-reset'
        );
        "#,
        &[&unverified_user_id],
    )
    .await?;

    // Check silent no-op for unknown, pre-registered, unverified, and SSO-only (password IS NULL) users
    for email in [
        "missing.contract@example.com",
        "pre-registered.contract@example.com",
        "unverified-reset.contract@example.com",
        "attendee.contract@example.com",
    ] {
        let reset = PasswordResetNotification {
            template_data: json!({"link": "https://example.test/reset-password/ignored"}),
            token_hash: hash_password_reset_token(email),
        };
        assert!(
            !uow.create_password_reset_token(email, &reset).await?,
            "expected silent no-op for {email}"
        );
        assert!(!uow.has_valid_password_reset_token(&reset.token_hash).await?);
    }

    // Issue a token for the eligible verified password user (contract-organizer)
    let first_hash = hash_password_reset_token("contract-reset-first");
    let first_reset = PasswordResetNotification {
        template_data: json!({"link": "https://example.test/reset-password/contract-reset-first"}),
        token_hash: first_hash,
    };
    assert!(
        uow.create_password_reset_token("ORGANIZER.CONTRACT@example.com", &first_reset)
            .await?
    );
    assert!(uow.has_valid_password_reset_token(&first_hash).await?);

    // Enforce the 2-minute per-user cooldown without replacing the active token
    let blocked_hash = hash_password_reset_token("contract-reset-blocked");
    let blocked_reset = PasswordResetNotification {
        template_data: json!({"link": "https://example.test/reset-password/contract-reset-blocked"}),
        token_hash: blocked_hash,
    };
    assert!(
        !uow.create_password_reset_token("organizer.contract@example.com", &blocked_reset)
            .await?
    );
    assert!(uow.has_valid_password_reset_token(&first_hash).await?);
    assert!(!uow.has_valid_password_reset_token(&blocked_hash).await?);

    // Backdate the token past the 2-minute cooldown and verify replacement succeeds
    uow.execute(
        "update password_reset_token set created_at = current_timestamp - interval '3 minutes' where user_id = $1::uuid;",
        &[&organizer_id()],
    )
    .await?;
    let replacement_hash = hash_password_reset_token("contract-reset-replacement");
    let replacement_reset = PasswordResetNotification {
        template_data: json!({"link": "https://example.test/reset-password/contract-reset-replacement"}),
        token_hash: replacement_hash,
    };
    assert!(
        uow.create_password_reset_token("organizer.contract@example.com", &replacement_reset)
            .await?
    );
    assert!(!uow.has_valid_password_reset_token(&first_hash).await?);
    assert!(uow.has_valid_password_reset_token(&replacement_hash).await?);

    Box::new(uow).rollback().await?;

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
async fn db_contracts_delete_expired_password_reset_tokens_deletes_expired_and_skips_when_locked()
-> Result<()> {
    // Setup a rolled-back unit of work with two expired tokens and one active token
    let uow = contract_unit_of_work().await?;
    let expired_hash_1 = hash_password_reset_token("contract-cleanup-expired-1");
    let expired_hash_2 = hash_password_reset_token("contract-cleanup-expired-2");
    let active_hash = hash_password_reset_token("contract-cleanup-active");
    let expired_slice_1 = expired_hash_1.as_slice();
    let expired_slice_2 = expired_hash_2.as_slice();
    let active_slice = active_hash.as_slice();
    uow.execute(
        "
        insert into password_reset_token (token_hash, created_at, user_id)
        values
            ($1::bytea, current_timestamp - interval '3 hours', $4::uuid),
            ($2::bytea, current_timestamp - interval '2 hours', $5::uuid),
            ($3::bytea, current_timestamp - interval '10 minutes', $6::uuid);
        ",
        &[
            &expired_slice_1,
            &expired_slice_2,
            &active_slice,
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
            "select pg_advisory_xact_lock(hashtextextended('ocg:password-reset-token-cleanup', 0));",
            &[],
        )
        .await?;
    let skipped = uow
        .delete_expired_password_reset_tokens(AUTH_CLEANUP_BATCH_SIZE)
        .await?;
    assert_eq!(skipped, 0);
    Box::new(lock_uow).rollback().await?;

    // Delete expired tokens in bounded batches after releasing the advisory lock
    let first_batch = uow.delete_expired_password_reset_tokens(1).await?;
    let second_batch = uow
        .delete_expired_password_reset_tokens(AUTH_CLEANUP_BATCH_SIZE)
        .await?;
    let third_batch = uow
        .delete_expired_password_reset_tokens(AUTH_CLEANUP_BATCH_SIZE)
        .await?;

    // Check only expired tokens were deleted and the active token remains
    assert_eq!(first_batch, 1);
    assert_eq!(second_batch, 1);
    assert_eq!(third_batch, 0);
    let remaining_expired: i64 = uow
        .fetch_scalar_one(
            "select count(*) from password_reset_token where token_hash in ($1::bytea, $2::bytea);",
            &[&expired_slice_1, &expired_slice_2],
        )
        .await?;
    assert_eq!(remaining_expired, 0);
    let remaining_active: i64 = uow
        .fetch_scalar_one(
            "select count(*) from password_reset_token where token_hash = $1::bytea;",
            &[&active_slice],
        )
        .await?;
    assert_eq!(remaining_active, 1);

    Box::new(uow).rollback().await?;

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_resend_email_verification_enforces_eligibility_and_cooldown() -> Result<()> {
    // Setup a rolled-back unit of work and an unverified registered user
    let uow = contract_unit_of_work().await?;
    let unverified_user_id = Uuid::new_v4();
    uow.execute(
        r#"
        insert into "user" (
            user_id,
            auth_hash,
            email,
            email_verified,
            password,
            registration_status,
            username
        ) values (
            $1::uuid,
            'contract_resend_hash',
            'resend-unverified.contract@example.com',
            false,
            'contract_password_hash',
            'registered',
            'contract-resend-unverified'
        );
        "#,
        &[&unverified_user_id],
    )
    .await?;

    // Check silent no-op for unknown, pre-registered, and already verified users
    for email in [
        "missing.contract@example.com",
        "pre-registered.contract@example.com",
        "organizer.contract@example.com",
    ] {
        let verification = EmailVerificationNotification {
            code: Uuid::new_v4(),
            template_data: json!({"link": "https://example.test/verify-email/ignored"}),
        };
        assert!(
            !uow.resend_email_verification(email, &verification).await?,
            "expected silent no-op for {email}"
        );
    }

    // Issue a verification code for the unverified registered user
    let first_verification = EmailVerificationNotification {
        code: Uuid::new_v4(),
        template_data: json!({"link": "https://example.test/verify-email/first"}),
    };
    assert!(
        uow.resend_email_verification(
            "RESEND-UNVERIFIED.CONTRACT@example.com",
            &first_verification
        )
        .await?
    );

    // Enforce the 2-minute per-user cooldown without replacing the active code
    let blocked_verification = EmailVerificationNotification {
        code: Uuid::new_v4(),
        template_data: json!({"link": "https://example.test/verify-email/blocked"}),
    };
    assert!(
        !uow.resend_email_verification(
            "resend-unverified.contract@example.com",
            &blocked_verification
        )
        .await?
    );
    let stored_code: Uuid = uow
        .fetch_scalar_one(
            "select email_verification_code_id from email_verification_code where user_id = $1::uuid;",
            &[&unverified_user_id],
        )
        .await?;
    assert_eq!(stored_code, first_verification.code);

    // Backdate the code past the 2-minute cooldown and verify replacement succeeds
    uow.execute(
        "update email_verification_code set created_at = current_timestamp - interval '3 minutes' where user_id = $1::uuid;",
        &[&unverified_user_id],
    )
    .await?;
    let replacement_verification = EmailVerificationNotification {
        code: Uuid::new_v4(),
        template_data: json!({"link": "https://example.test/verify-email/replacement"}),
    };
    assert!(
        uow.resend_email_verification(
            "resend-unverified.contract@example.com",
            &replacement_verification
        )
        .await?
    );
    let stored_code: Uuid = uow
        .fetch_scalar_one(
            "select email_verification_code_id from email_verification_code where user_id = $1::uuid;",
            &[&unverified_user_id],
        )
        .await?;
    assert_eq!(stored_code, replacement_verification.code);

    Box::new(uow).rollback().await?;

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_reset_password_consumes_token_rotates_auth_hash_and_invalidates_sessions()
-> Result<()> {
    // Setup a rolled-back unit of work, capture the initial auth_hash, and issue a reset token
    let uow = contract_unit_of_work().await?;
    let before = uow
        .get_user_by_id(&organizer_id())
        .await?
        .expect("contract organizer should exist");
    let token_hash = hash_password_reset_token("contract-single-use-reset");
    let reset = PasswordResetNotification {
        template_data: json!({"link": "https://example.test/reset-password/contract-single-use-reset"}),
        token_hash,
    };
    assert!(
        uow.create_password_reset_token("organizer.contract@example.com", &reset)
            .await?
    );

    // Consume the token once and verify password update, token deletion, and auth_hash rotation
    uow.reset_password(&token_hash, "contract_new_password_hash").await?;
    assert!(!uow.has_valid_password_reset_token(&token_hash).await?);
    assert_eq!(
        uow.get_user_password(&organizer_id()).await?.as_deref(),
        Some("contract_new_password_hash")
    );
    let after = uow
        .get_user_by_id(&organizer_id())
        .await?
        .expect("contract organizer should still exist");
    assert_ne!(after.auth_hash, before.auth_hash);

    // Check replaying the consumed token returns an OCG01 rejection
    let replay_err = uow
        .reset_password(&token_hash, "contract_replayed_password_hash")
        .await
        .expect_err("replayed reset token should fail");
    assert_ocg01(
        &replay_err,
        "password reset failed: invalid or expired token",
    );

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
