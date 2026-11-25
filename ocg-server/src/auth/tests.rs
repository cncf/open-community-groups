use std::{
    collections::HashMap,
    sync::{Arc, Mutex, mpsc},
    time::Duration,
};

use anyhow::anyhow;
use axum::{Form, Json, Router, http::StatusCode, routing::post};
use axum_login::AuthUser;
use chrono::{Duration as ChronoDuration, Utc};
use oauth2::reqwest as oauth2_reqwest;
use openidconnect as oidc;
use password_auth::{VerifyError, generate_hash, is_hash_obsolete};
use serde_json::json;
use tokio::{net::TcpListener, sync::oneshot, time::timeout};
use uuid::Uuid;

use crate::{
    config::{
        HttpClientConfig, OAuth2Config, OAuth2Provider, OAuth2ProviderConfig, OidcConfig,
        OidcProvider, OidcProviderConfig,
    },
    db::{DynDB, mock::MockDB},
    services::blocking::BlockingExecutor,
    test_util::wait_until,
    types::user::{GitHubUserProvider, LinuxFoundationUserProvider, UserProvider},
};

use super::*;

#[tokio::test]
async fn test_authenticate_dispatches_password_credentials() {
    // Setup database mock
    let user = User {
        password: Some(generate_hash("correct-password")),
        ..sample_user()
    };
    let mut db = MockDB::new();
    expect_user_by_username(&mut db, Some(user));
    let db: DynDB = Arc::new(db);

    // Execute authentication
    let backend = authn_backend(db).await;
    let user = axum_login::AuthnBackend::authenticate(
        &backend,
        Credentials::Password(PasswordCredentials {
            password: "correct-password".to_string(),
            username: "test-user".to_string(),
        }),
    )
    .await
    .unwrap()
    .unwrap();

    // Check the user is returned without the password hash
    assert!(user.password.is_none());
    assert_eq!(user.email, "user@example.com");
    assert_eq!(user.username, "test-user");
}

#[tokio::test]
async fn test_authenticate_maps_password_backend_error_to_auth_error() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_user_by_username()
        .times(1)
        .withf(|username| username == "test-user")
        .returning(|_| Err(anyhow!("database unavailable")));
    let db: DynDB = Arc::new(db);

    // Execute authentication
    let backend = authn_backend(db).await;
    let result = axum_login::AuthnBackend::authenticate(
        &backend,
        Credentials::Password(PasswordCredentials {
            password: "correct-password".to_string(),
            username: "test-user".to_string(),
        }),
    )
    .await;

    // Check result
    match result {
        Err(AuthError(err)) => assert!(err.to_string().contains("database unavailable")),
        Ok(_) => panic!("expected password backend error"),
    }
}

#[tokio::test]
async fn test_authenticate_maps_oauth2_backend_error_to_auth_error() {
    // Setup backend without configured providers
    let db: DynDB = Arc::new(MockDB::new());
    let backend = authn_backend(db).await;

    // Execute authentication
    let result = axum_login::AuthnBackend::authenticate(
        &backend,
        Credentials::OAuth2(OAuth2Credentials {
            code: "code".to_string(),
            pkce_verifier: oauth2::PkceCodeVerifier::new("verifier".to_string()),
            provider: OAuth2Provider::GitHub,
        }),
    )
    .await;

    // Check result
    match result {
        Err(AuthError(err)) => assert!(err.to_string().contains("oauth2 provider not found")),
        Ok(_) => panic!("expected oauth2 backend error"),
    }
}

#[tokio::test]
async fn test_authenticate_maps_oidc_backend_error_to_auth_error() {
    // Setup backend without configured providers
    let db: DynDB = Arc::new(MockDB::new());
    let backend = authn_backend(db).await;

    // Execute authentication
    let result = axum_login::AuthnBackend::authenticate(
        &backend,
        Credentials::Oidc(OidcCredentials {
            code: "code".to_string(),
            nonce: oidc::Nonce::new("nonce".to_string()),
            pkce_verifier: oidc::PkceCodeVerifier::new("verifier".to_string()),
            provider: OidcProvider::LinuxFoundation,
        }),
    )
    .await;

    // Check result
    match result {
        Err(AuthError(err)) => assert!(err.to_string().contains("oidc provider not found")),
        Ok(_) => panic!("expected oidc backend error"),
    }
}

#[tokio::test]
async fn test_authenticate_oauth2_sends_pkce_verifier_in_token_exchange() {
    // Setup local token endpoint that captures the decoded form body
    let (token_url, body_rx) = spawn_token_capture_server().await;
    let mut provider_cfg = sample_oauth2_provider_config();
    provider_cfg.token_url = token_url;
    let oauth2_cfg = HashMap::from([(OAuth2Provider::GitHub, provider_cfg)]);
    let backend = AuthnBackend::new(
        BlockingExecutor::new(1),
        Arc::new(MockDB::new()),
        &HttpClientConfig::default(),
        &oauth2_cfg,
        &HashMap::new(),
    )
    .await
    .unwrap();

    // Execute authentication against the fake token endpoint
    let err = backend
        .authenticate_oauth2(OAuth2Credentials {
            code: "test-code".to_string(),
            pkce_verifier: oauth2::PkceCodeVerifier::new("test-pkce-verifier".to_string()),
            provider: OAuth2Provider::GitHub,
        })
        .await
        .unwrap_err();

    // Check the endpoint rejection and captured PKCE verifier parameter
    let err_chain = format!("{err:#}");
    assert!(err_chain.contains("invalid_grant"), "{err_chain}");
    let params = timeout(Duration::from_secs(5), body_rx)
        .await
        .expect("token endpoint should receive the exchange request")
        .expect("token request form parameters should be captured");
    assert_eq!(params.get("code").map(String::as_str), Some("test-code"));
    assert_eq!(
        params.get("code_verifier").map(String::as_str),
        Some("test-pkce-verifier")
    );
}

#[tokio::test]
async fn test_authenticate_oidc_sends_pkce_verifier_in_token_exchange() {
    // Setup local token endpoint and OIDC client pointing at it
    let (token_url, body_rx) = spawn_token_capture_server().await;
    let metadata = oidc::core::CoreProviderMetadata::new(
        oidc::IssuerUrl::new("https://issuer.example".to_string()).unwrap(),
        oidc::AuthUrl::new("https://issuer.example/authorize".to_string()).unwrap(),
        oidc::JsonWebKeySetUrl::new("https://issuer.example/jwks".to_string()).unwrap(),
        vec![oidc::ResponseTypes::new(vec![
            oidc::core::CoreResponseType::Code,
        ])],
        vec![oidc::core::CoreSubjectIdentifierType::Public],
        vec![oidc::core::CoreJwsSigningAlgorithm::RsaSsaPkcs1V15Sha256],
        oidc::EmptyAdditionalProviderMetadata::default(),
    )
    .set_token_endpoint(Some(oidc::TokenUrl::new(token_url).unwrap()))
    .set_jwks(oidc::JsonWebKeySet::new(vec![]));
    let client = oidc::core::CoreClient::from_provider_metadata(
        metadata,
        oidc::ClientId::new("client-id".to_string()),
        Some(oidc::ClientSecret::new("client-secret".to_string())),
    )
    .set_redirect_uri(
        oidc::RedirectUrl::new("https://example.com/oidc/callback".to_string()).unwrap(),
    );
    let mut backend = authn_backend(Arc::new(MockDB::new())).await;
    backend.oidc_providers.insert(
        OidcProvider::LinuxFoundation,
        Arc::new(OidcProviderDetails {
            client,
            scopes: vec!["openid".to_string()],
        }),
    );

    // Execute authentication against the fake token endpoint
    let err = backend
        .authenticate_oidc(OidcCredentials {
            code: "test-code".to_string(),
            nonce: oidc::Nonce::new("nonce".to_string()),
            pkce_verifier: oidc::PkceCodeVerifier::new("test-pkce-verifier".to_string()),
            provider: OidcProvider::LinuxFoundation,
        })
        .await
        .unwrap_err();

    // Check the endpoint rejection and captured PKCE verifier parameter
    let err_chain = format!("{err:#}");
    assert!(err_chain.contains("invalid_grant"), "{err_chain}");
    let params = timeout(Duration::from_secs(5), body_rx)
        .await
        .expect("token endpoint should receive the exchange request")
        .expect("token request form parameters should be captured");
    assert_eq!(params.get("code").map(String::as_str), Some("test-code"));
    assert_eq!(
        params.get("code_verifier").map(String::as_str),
        Some("test-pkce-verifier")
    );
}

#[tokio::test]
async fn test_authenticate_password_returns_none_when_password_is_incorrect() {
    // Setup database mock
    let user = User {
        password: Some(generate_hash("correct-password")),
        ..sample_user()
    };
    let mut db = MockDB::new();
    expect_user_by_username(&mut db, Some(user));
    let db: DynDB = Arc::new(db);

    // Execute authentication
    let backend = authn_backend(db).await;
    let result = backend
        .authenticate_password(PasswordCredentials {
            password: "wrong-password".to_string(),
            username: "test-user".to_string(),
        })
        .await
        .unwrap();

    // Check result
    assert!(result.is_none());
}

#[tokio::test]
async fn test_authenticate_password_returns_none_when_password_is_missing() {
    // Setup database mock
    let user = User {
        password: None,
        ..sample_user()
    };
    let mut db = MockDB::new();
    expect_user_by_username(&mut db, Some(user));
    let db: DynDB = Arc::new(db);

    // Execute authentication
    let backend = authn_backend(db).await;
    let result = backend
        .authenticate_password(PasswordCredentials {
            password: "correct-password".to_string(),
            username: "test-user".to_string(),
        })
        .await
        .unwrap();

    // Check result
    assert!(result.is_none());
}

#[tokio::test]
async fn test_authenticate_password_returns_none_when_user_not_found() {
    // Setup database mock
    let mut db = MockDB::new();
    expect_user_by_username(&mut db, None);
    let db: DynDB = Arc::new(db);

    // Execute authentication
    let backend = authn_backend(db).await;
    let result = backend
        .authenticate_password(PasswordCredentials {
            password: "correct-password".to_string(),
            username: "test-user".to_string(),
        })
        .await
        .unwrap();

    // Check result
    assert!(result.is_none());
}

#[tokio::test]
async fn test_authenticate_password_runs_dummy_verification_when_password_is_missing() {
    // Setup database mock returning an SSO-only user without a password hash
    let user = User {
        password: None,
        ..sample_user()
    };
    let mut db = MockDB::new();
    expect_user_by_username(&mut db, Some(user));

    // Check authentication waits for the blocking executor permit and returns None
    assert_dummy_password_verification_uses_blocking_executor(Arc::new(db)).await;
}

#[tokio::test]
async fn test_authenticate_password_runs_dummy_verification_when_user_not_found() {
    // Setup database mock returning no user
    let mut db = MockDB::new();
    expect_user_by_username(&mut db, None);

    // Check authentication waits for the blocking executor permit and returns None
    assert_dummy_password_verification_uses_blocking_executor(Arc::new(db)).await;
}

#[test]
fn test_dummy_password_hash_matches_current_argon2_defaults() {
    // Check the dummy hash uses current default parameters and executes Argon2id
    assert_eq!(is_hash_obsolete(DUMMY_PASSWORD_HASH), Ok(false));
    assert!(
        verify_password(DUMMY_TEST_PASSWORD, DUMMY_PASSWORD_HASH).is_ok(),
        "expected dummy hash to verify against its precomputed input (proving full Argon2id work)"
    );
    assert!(matches!(
        verify_password("other-password", DUMMY_PASSWORD_HASH),
        Err(VerifyError::PasswordInvalid)
    ));
}

#[test]
fn test_from_user_to_external_user_profile_drops_password() {
    // Setup input user
    let mut user = sample_user();
    user.has_password = Some(true);
    user.password = Some("super-secret-password".to_string());

    // Execute conversion
    let summary = ExternalUserProfile::from(user);

    // Check result
    assert!(summary.has_password.unwrap());
    assert!(summary.password.is_none());
    assert_eq!(summary.provider, Some(sample_user_provider()));
}

#[tokio::test]
async fn test_get_or_sign_up_external_user_merges_provider_into_existing_user() {
    // Setup database mock
    let mut db = MockDB::new();
    let existing_user = sample_user();
    let existing_user_id = existing_user.user_id;
    let incoming_provider = sample_linuxfoundation_user_provider();
    let profile = sample_external_user_profile(Some(incoming_provider.clone()));

    expect_lf_identity_lookup(&mut db, None);
    expect_email_lookup(&mut db, Some(existing_user));
    db.expect_update_user_provider()
        .times(1)
        .withf(move |user_id, provider| {
            *user_id == existing_user_id && provider == &incoming_provider
        })
        .returning(|_, _| Ok(()));
    db.expect_sign_up_user().times(0);
    let db: DynDB = Arc::new(db);

    // Execute helper
    let backend = authn_backend(db).await;
    let user = backend.get_or_sign_up_external_user(&profile).await.unwrap();

    // Check result
    assert_eq!(
        user.provider,
        Some(UserProvider {
            github: Some(GitHubUserProvider {
                username: "test-user-gh".to_string(),
            }),
            linuxfoundation: Some(LinuxFoundationUserProvider {
                username: "test-user-lf".to_string(),

                issuer: Some("https://issuer.example.com".to_string()),
                subject: Some("auth0|test-user".to_string()),
            }),
        })
    );
}

#[tokio::test]
async fn test_get_or_sign_up_external_user_rejects_linuxfoundation_identity_relink() {
    // Setup database mock
    let mut db = MockDB::new();
    let mut existing_provider = sample_user_provider();
    existing_provider.linuxfoundation = Some(LinuxFoundationUserProvider {
        username: "other-lf-user".to_string(),

        issuer: Some("https://issuer.example.com".to_string()),
        subject: Some("auth0|other-user".to_string()),
    });
    let existing_user = User {
        provider: Some(existing_provider),
        ..sample_user()
    };
    let profile = sample_external_user_profile(Some(sample_linuxfoundation_user_provider()));

    expect_lf_identity_lookup(&mut db, None);
    expect_email_lookup(&mut db, Some(existing_user));
    db.expect_update_user_provider().times(0);
    db.expect_sign_up_user().times(0);
    let db: DynDB = Arc::new(db);

    // Execute helper
    let backend = authn_backend(db).await;
    let error = backend.get_or_sign_up_external_user(&profile).await.unwrap_err();

    // Check result
    assert!(error.to_string().contains(EXTERNAL_AUTH_IDENTITY_CONFLICT_ERROR));
}

#[tokio::test]
async fn test_get_or_sign_up_external_user_ignores_linuxfoundation_username_mismatch_without_identity()
 {
    // Setup database mock
    let mut db = MockDB::new();
    let existing_user = User {
        provider: Some(sample_linuxfoundation_username_only_user_provider(
            "other-lf-user",
        )),
        ..sample_user()
    };
    let existing_user_id = existing_user.user_id;
    let incoming_provider = sample_linuxfoundation_user_provider();
    let profile = sample_external_user_profile(Some(incoming_provider.clone()));

    expect_lf_identity_lookup(&mut db, None);
    expect_email_lookup(&mut db, Some(existing_user));
    db.expect_update_user_provider()
        .times(1)
        .withf(move |user_id, provider| {
            *user_id == existing_user_id && provider == &incoming_provider
        })
        .returning(|_, _| Ok(()));
    db.expect_sign_up_user().times(0);
    let db: DynDB = Arc::new(db);

    // Execute helper
    let backend = authn_backend(db).await;
    let user = backend.get_or_sign_up_external_user(&profile).await.unwrap();

    // Check result
    assert_eq!(user.provider, Some(sample_linuxfoundation_user_provider()));
}

#[tokio::test]
async fn test_get_or_sign_up_external_user_reconciles_linuxfoundation_identity_before_email() {
    // Setup database mock
    let mut db = MockDB::new();
    let existing_user = User {
        provider: Some(sample_linuxfoundation_user_provider()),
        ..sample_user()
    };
    let existing_user_id = existing_user.user_id;
    let mut updated_user = existing_user.clone();
    updated_user.email = "new@example.com".to_string();
    updated_user.name = "New Test User".to_string();
    let mut profile = sample_external_user_profile(Some(sample_linuxfoundation_user_provider()));
    profile.email = "new@example.com".to_string();
    profile.name = "New Test User".to_string();

    expect_lf_identity_lookup(&mut db, Some(existing_user));
    db.expect_update_user_external_auth()
        .times(1)
        .withf(move |user_id, summary| {
            *user_id == existing_user_id
                && summary.email == "new@example.com"
                && summary.name == "New Test User"
                && summary.provider == Some(sample_linuxfoundation_user_provider())
        })
        .returning(move |_, _| Ok(updated_user.clone()));
    db.expect_get_user_by_email_for_external_auth().times(0);
    db.expect_update_user_provider().times(0);
    db.expect_sign_up_user().times(0);
    let db: DynDB = Arc::new(db);

    // Execute helper
    let backend = authn_backend(db).await;
    let user = backend.get_or_sign_up_external_user(&profile).await.unwrap();

    // Check result
    assert_eq!(user.email, "new@example.com");
    assert_eq!(user.name, "New Test User");
    assert_eq!(user.user_id, existing_user_id);
}

#[tokio::test]
async fn test_get_or_sign_up_external_user_sets_provider_for_existing_user_without_provider() {
    // Setup database mock
    let mut db = MockDB::new();
    let existing_user = sample_user_without_provider();
    let existing_user_id = existing_user.user_id;
    let incoming_provider = sample_user_provider();
    let profile = sample_external_user_profile(Some(incoming_provider.clone()));

    expect_email_lookup(&mut db, Some(existing_user));
    db.expect_update_user_provider()
        .times(1)
        .withf(move |user_id, provider| {
            *user_id == existing_user_id && provider == &incoming_provider
        })
        .returning(|_, _| Ok(()));
    db.expect_sign_up_user().times(0);
    let db: DynDB = Arc::new(db);

    // Execute helper
    let backend = authn_backend(db).await;
    let user = backend.get_or_sign_up_external_user(&profile).await.unwrap();

    // Check result
    assert_eq!(user.provider, Some(sample_user_provider()));
}

#[tokio::test]
async fn test_get_or_sign_up_external_user_skips_provider_update_when_unchanged() {
    // Setup database mock
    let mut db = MockDB::new();
    let existing_user = sample_user();
    let profile = sample_external_user_profile(Some(sample_user_provider()));

    expect_email_lookup(&mut db, Some(existing_user));
    db.expect_update_user_provider().times(0);
    db.expect_sign_up_user().times(0);
    let db: DynDB = Arc::new(db);

    // Execute helper
    let backend = authn_backend(db).await;
    let user = backend.get_or_sign_up_external_user(&profile).await.unwrap();

    // Check result
    assert_eq!(user.provider, Some(sample_user_provider()));
}

#[tokio::test]
async fn test_get_or_sign_up_external_user_signs_up_new_user() {
    // Setup database mock
    let mut db = MockDB::new();
    let provider = sample_user_provider();
    let profile = sample_external_user_profile(Some(provider.clone()));
    let signed_up_user = sample_user();

    expect_email_lookup(&mut db, None);
    db.expect_update_user_provider().times(0);
    db.expect_sign_up_user()
        .times(1)
        .withf(move |summary, email_verified, verification| {
            summary.email == "user@example.com"
                && summary.name == "Test User"
                && summary.provider == Some(provider.clone())
                && summary.username == "test-user"
                && *email_verified
                && verification.is_none()
        })
        .returning(move |_, _, _| Ok((signed_up_user.clone(), None)));
    let db: DynDB = Arc::new(db);

    // Execute helper
    let backend = authn_backend(db).await;
    let user = backend.get_or_sign_up_external_user(&profile).await.unwrap();

    // Check result
    assert_eq!(user.provider, Some(sample_user_provider()));
}

#[tokio::test]
async fn test_get_or_sign_up_external_user_activates_pre_registered_user() {
    // Setup database mock
    let mut db = MockDB::new();
    let mut pre_registered_user = sample_user();
    pre_registered_user.registration_status = "pre-registered".to_string();
    let pre_registered_user_id = pre_registered_user.user_id;
    let activated_user = sample_user();
    let profile = sample_external_user_profile(Some(sample_linuxfoundation_user_provider()));

    expect_lf_identity_lookup(&mut db, None);
    expect_email_lookup(&mut db, Some(pre_registered_user));
    db.expect_activate_pre_registered_user_external_provider()
        .times(1)
        .withf(move |user_id, summary| {
            *user_id == pre_registered_user_id
                && summary.email == "user@example.com"
                && summary.provider == Some(sample_linuxfoundation_user_provider())
        })
        .returning(move |_, _| Ok(activated_user.clone()));
    db.expect_update_user_provider().times(0);
    db.expect_sign_up_user().times(0);
    let db: DynDB = Arc::new(db);

    // Execute helper
    let backend = authn_backend(db).await;
    let user = backend.get_or_sign_up_external_user(&profile).await.unwrap();

    // Check result
    assert_eq!(user.registration_status, "registered");
}

#[tokio::test]
async fn test_get_or_sign_up_external_user_skips_provider_update_when_missing() {
    // Setup database mock
    let mut db = MockDB::new();
    let existing_user = sample_user();
    let profile = sample_external_user_profile(None);

    expect_email_lookup(&mut db, Some(existing_user));
    db.expect_update_user_provider().times(0);
    db.expect_sign_up_user().times(0);
    let db: DynDB = Arc::new(db);

    // Execute helper
    let backend = authn_backend(db).await;
    let user = backend.get_or_sign_up_external_user(&profile).await.unwrap();

    // Check result
    assert_eq!(user.provider, Some(sample_user_provider()));
}

#[tokio::test]
async fn test_get_user_maps_db_error_to_auth_error() {
    // Setup database mock
    let user_id = Uuid::new_v4();
    let mut db = MockDB::new();
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(|_| Err(anyhow!("database unavailable")));
    let db: DynDB = Arc::new(db);

    // Execute get user
    let backend = authn_backend(db).await;
    let result = axum_login::AuthnBackend::get_user(&backend, &user_id).await;

    // Check result
    match result {
        Err(AuthError(err)) => assert!(err.to_string().contains("database unavailable")),
        Ok(_) => panic!("expected get_user backend error"),
    }
}

#[tokio::test]
async fn test_get_user_returns_none_when_user_not_found() {
    // Setup database mock
    let user_id = Uuid::new_v4();
    let mut db = MockDB::new();
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(|_| Ok(None));
    let db: DynDB = Arc::new(db);

    // Execute get user
    let backend = authn_backend(db).await;
    let result = axum_login::AuthnBackend::get_user(&backend, &user_id).await.unwrap();

    // Check result
    assert!(result.is_none());
}

#[tokio::test]
async fn test_setup_oidc_providers_rejects_invalid_issuer_url() {
    // Setup invalid OIDC configuration
    let mut oidc_cfg: OidcConfig = HashMap::new();
    let mut provider_cfg = sample_oidc_provider_config();
    provider_cfg.issuer_url = "invalid-url".to_string();
    oidc_cfg.insert(OidcProvider::LinuxFoundation, provider_cfg);
    let http_client = oauth2_reqwest::ClientBuilder::new().build().unwrap();

    // Execute provider setup
    let result = AuthnBackend::setup_oidc_providers(&oidc_cfg, http_client).await;

    // Check result
    assert!(result.is_err());
}

#[test]
fn test_setup_oauth2_providers_builds_provider_map_when_config_is_valid() {
    // Setup valid OAuth2 configuration
    let mut oauth2_cfg: OAuth2Config = HashMap::new();
    let provider_cfg = sample_oauth2_provider_config();
    oauth2_cfg.insert(OAuth2Provider::GitHub, provider_cfg.clone());

    // Execute provider setup
    let providers = AuthnBackend::setup_oauth2_providers(&oauth2_cfg).unwrap();

    // Check result
    assert_eq!(providers.len(), 1);
    assert!(providers.contains_key(&OAuth2Provider::GitHub));
    assert_eq!(
        providers.get(&OAuth2Provider::GitHub).unwrap().scopes,
        provider_cfg.scopes
    );
}

#[test]
fn test_setup_oauth2_providers_rejects_invalid_urls() {
    // Setup configurations with one invalid URL each
    let valid_cfg = sample_oauth2_provider_config();
    let cases = [
        (
            "invalid auth url",
            OAuth2ProviderConfig {
                auth_url: "invalid-url".to_string(),
                ..valid_cfg.clone()
            },
        ),
        (
            "invalid redirect uri",
            OAuth2ProviderConfig {
                redirect_uri: "invalid-url".to_string(),
                ..valid_cfg.clone()
            },
        ),
        (
            "invalid token url",
            OAuth2ProviderConfig {
                token_url: "invalid-url".to_string(),
                ..valid_cfg
            },
        ),
    ];

    for (case, provider_cfg) in cases {
        let oauth2_cfg: OAuth2Config = HashMap::from([(OAuth2Provider::GitHub, provider_cfg)]);

        // Execute provider setup
        let result = AuthnBackend::setup_oauth2_providers(&oauth2_cfg);

        // Check result
        assert!(result.is_err(), "{case}");
    }
}

#[test]
fn test_user_debug_does_not_expose_sensitive_fields() {
    // Setup input user
    let mut user = sample_user();
    user.auth_hash = "private-auth-hash".to_string();
    user.password = Some("private-password-hash".to_string());

    // Execute debug format
    let output = format!("{user:?}");

    // Check result
    assert!(output.contains("User"));
    assert!(!output.contains("private-auth-hash"));
    assert!(!output.contains("private-password-hash"));
}

#[test]
fn test_user_is_profile_complete_requires_title_bio_and_profile_link() {
    // Setup profile field combinations: (case, bio, github_url, title, expected)
    let bio = Some("Builds community tools.");
    let github_url = Some("https://github.com/test-user");
    let title = Some("Software Engineer");
    let cases = [
        ("bio missing", None, github_url, title, false),
        ("profile link missing", bio, None, title, false),
        ("title missing", bio, github_url, None, false),
        (
            "whitespace-only values",
            Some("   "),
            Some("\n\t"),
            Some(" "),
            false,
        ),
        ("required fields present", bio, github_url, title, true),
    ];

    for (case, bio, github_url, title, expected) in cases {
        let user = User {
            bio: bio.map(String::from),
            github_url: github_url.map(String::from),
            title: title.map(String::from),
            ..sample_user()
        };

        // Check profile completion result
        assert_eq!(user.is_profile_complete(), expected, "{case}");
    }
}

#[test]
fn test_external_user_profile_debug_does_not_expose_password() {
    // Setup input summary
    let summary = ExternalUserProfile {
        email: "user@example.com".to_string(),
        name: "Test User".to_string(),
        username: "test-user".to_string(),
        has_password: Some(true),
        password: Some("private-password-hash".to_string()),
        provider: Some(sample_user_provider()),
    };

    // Execute debug format
    let output = format!("{summary:?}");

    // Check result
    assert!(output.contains("ExternalUserProfile"));
    assert!(!output.contains("private-password-hash"));
}

#[test]
fn test_external_user_profile_from_oidc_id_token_claims_extracts_verified_user() {
    // Setup valid claims
    let claims = sample_oidc_claims(
        Some("user@example.com"),
        Some(true),
        Some("Test User"),
        Some("test-user"),
    );

    // Execute conversion
    let result = ExternalUserProfile::from_oidc_id_token_claims(&claims).unwrap();

    // Check result
    assert_eq!(result.email, "user@example.com");
    assert_eq!(result.name, "Test User");
    assert_eq!(
        result.provider,
        Some(UserProvider {
            github: None,
            linuxfoundation: Some(LinuxFoundationUserProvider {
                username: "test-user".to_string(),

                issuer: Some("https://issuer.example.com".to_string()),
                subject: Some("subject".to_string()),
            }),
        })
    );
    assert_eq!(result.username, "test-user");
    assert_eq!(result.has_password, Some(false));
    assert!(result.password.is_none());
}

#[test]
fn test_external_user_profile_from_oidc_id_token_claims_rejects_incomplete_claims() {
    // Setup claims: (case, email, email_verified, name, nickname, expected error)
    let email = Some("user@example.com");
    let name = Some("Test User");
    let nickname = Some("test-user");
    let cases = [
        (
            "email missing",
            None,
            Some(true),
            name,
            nickname,
            "email missing",
        ),
        (
            "name missing",
            email,
            Some(true),
            None,
            nickname,
            "name missing",
        ),
        (
            "nickname missing",
            email,
            Some(true),
            name,
            None,
            "nickname missing",
        ),
        (
            "email verification missing",
            email,
            None,
            name,
            nickname,
            EXTERNAL_AUTH_OIDC_EMAIL_NOT_VERIFIED_ERROR,
        ),
        (
            "email unverified",
            email,
            Some(false),
            name,
            nickname,
            EXTERNAL_AUTH_OIDC_EMAIL_NOT_VERIFIED_ERROR,
        ),
    ];

    for (case, email, email_verified, name, nickname, expected_error) in cases {
        let claims = sample_oidc_claims(email, email_verified, name, nickname);

        // Execute conversion
        let result = ExternalUserProfile::from_oidc_id_token_claims(&claims);

        // Check result
        let err = result.expect_err(case);
        assert!(err.to_string().contains(expected_error), "{case}: {err}");
    }
}

#[test]
fn test_user_session_auth_hash_matches_auth_hash_bytes() {
    // Setup input user
    let mut user = sample_user();
    user.auth_hash = "private-auth-hash".to_string();

    // Execute auth hash retrieval
    let hash = user.session_auth_hash();

    // Check result
    assert_eq!(hash, user.auth_hash.as_bytes());
}

// Helpers.

/// Preimage used to precompute `DUMMY_PASSWORD_HASH` so tests can verify real
/// Argon2id computation and confirm it still never authenticates a missing or
/// SSO-only user.
const DUMMY_TEST_PASSWORD: &str = "ocg-dummy-password";

/// Verifies `authenticate_password` schedules dummy verification on the
/// blocking executor before returning `None`, even if the caller supplies the
/// dummy hash preimage.
async fn assert_dummy_password_verification_uses_blocking_executor(db: DynDB) {
    // Setup a single-permit executor and occupy its only permit
    let executor = BlockingExecutor::new(1);
    let (release_tx, release_rx) = mpsc::channel::<()>();
    let holder_executor = executor.clone();
    let holder = tokio::spawn(async move {
        holder_executor
            .run(move || {
                let _ = release_rx.recv();
            })
            .await
            .unwrap();
    });
    wait_until(|| executor.available_permits() == 0).await;

    // Start password authentication while the blocking executor permit is held
    let backend = AuthnBackend::new(
        executor.clone(),
        db,
        &HttpClientConfig::default(),
        &HashMap::new(),
        &HashMap::new(),
    )
    .await
    .unwrap();
    let mut auth_task = tokio::spawn(async move {
        backend
            .authenticate_password(PasswordCredentials {
                password: DUMMY_TEST_PASSWORD.to_string(),
                username: "test-user".to_string(),
            })
            .await
    });

    // Check authentication stays pending until the blocking permit is released
    assert!(
        timeout(Duration::from_millis(50), &mut auth_task).await.is_err(),
        "dummy password verification should wait for a blocking executor permit"
    );

    // Release the blocking permit and check authentication resolves to None
    release_tx.send(()).unwrap();
    holder.await.unwrap();
    let result = auth_task.await.unwrap().unwrap();
    assert!(result.is_none());
    assert_eq!(executor.available_permits(), 1);
}

/// Expect the email lookup for the sample profile to return the user.
fn expect_email_lookup(db: &mut MockDB, user: Option<User>) {
    db.expect_get_user_by_email_for_external_auth()
        .times(1)
        .withf(|email| email == "user@example.com")
        .returning(move |_| Ok(user.clone()));
}

/// Expect the LF identity lookup for the sample profile to return the user.
fn expect_lf_identity_lookup(db: &mut MockDB, user: Option<User>) {
    db.expect_get_user_by_linuxfoundation_identity_for_external_auth()
        .times(1)
        .withf(|issuer, subject| {
            issuer == "https://issuer.example.com" && subject == "auth0|test-user"
        })
        .returning(move |_, _| Ok(user.clone()));
}

/// Expect the username lookup for the sample credentials to return the user.
fn expect_user_by_username(db: &mut MockDB, user: Option<User>) {
    db.expect_get_user_by_username()
        .times(1)
        .withf(|username| username == "test-user")
        .returning(move |_| Ok(user.clone()));
}

async fn authn_backend(db: DynDB) -> AuthnBackend {
    let http_client_cfg = HttpClientConfig::default();
    let oidc_cfg: OidcConfig = HashMap::new();
    let oauth2_cfg: OAuth2Config = HashMap::new();
    AuthnBackend::new(
        BlockingExecutor::new(1),
        db,
        &http_client_cfg,
        &oauth2_cfg,
        &oidc_cfg,
    )
    .await
    .unwrap()
}

fn sample_oauth2_provider_config() -> OAuth2ProviderConfig {
    OAuth2ProviderConfig {
        auth_url: "https://github.com/login/oauth/authorize".to_string(),
        client_id: "client-id".to_string(),
        client_secret: "client-secret".to_string(),
        redirect_uri: "https://example.com/auth/callback".to_string(),
        scopes: vec!["user:email".to_string()],
        token_url: "https://github.com/login/oauth/access_token".to_string(),
    }
}

fn sample_oidc_claims(
    email: Option<&str>,
    email_verified: Option<bool>,
    name: Option<&str>,
    nickname: Option<&str>,
) -> oidc::IdTokenClaims<oidc::EmptyAdditionalClaims, oidc::core::CoreGenderClaim> {
    let mut standard_claims = oidc::StandardClaims::<oidc::core::CoreGenderClaim>::new(
        oidc::SubjectIdentifier::new("subject".to_string()),
    );
    standard_claims =
        standard_claims.set_email(email.map(|value| oidc::EndUserEmail::new(value.to_string())));
    standard_claims = standard_claims.set_email_verified(email_verified);
    standard_claims = standard_claims.set_name(
        name.map(|value| LocalizedClaim::from(oidc::EndUserName::new(value.to_string()))),
    );
    standard_claims = standard_claims.set_nickname(
        nickname.map(|value| LocalizedClaim::from(oidc::EndUserNickname::new(value.to_string()))),
    );

    oidc::IdTokenClaims::new(
        oidc::IssuerUrl::new("https://issuer.example.com".to_string()).unwrap(),
        vec![oidc::Audience::new("client-id".to_string())],
        Utc::now() + ChronoDuration::hours(1),
        Utc::now(),
        standard_claims,
        oidc::EmptyAdditionalClaims {},
    )
}

fn sample_oidc_provider_config() -> OidcProviderConfig {
    OidcProviderConfig {
        client_id: "client-id".to_string(),
        client_secret: "client-secret".to_string(),
        issuer_url: "https://issuer.example.com".to_string(),
        redirect_uri: "https://example.com/oidc/callback".to_string(),
        scopes: vec![
            "openid".to_string(),
            "email".to_string(),
            "profile".to_string(),
        ],
    }
}

fn sample_user() -> User {
    User {
        auth_hash: "session-auth-hash".to_string(),
        email: "user@example.com".to_string(),
        email_verified: true,
        name: "Test User".to_string(),
        registration_status: "registered".to_string(),
        user_id: Uuid::new_v4(),
        username: "test-user".to_string(),

        provider: Some(sample_user_provider()),
        ..User::default()
    }
}

fn sample_user_without_provider() -> User {
    User {
        provider: None,
        ..sample_user()
    }
}

fn sample_external_user_profile(provider: Option<UserProvider>) -> ExternalUserProfile {
    ExternalUserProfile {
        email: "user@example.com".to_string(),
        name: "Test User".to_string(),
        username: "test-user".to_string(),
        has_password: Some(false),
        password: None,
        provider,
    }
}

fn sample_user_provider() -> UserProvider {
    UserProvider {
        github: Some(GitHubUserProvider {
            username: "test-user-gh".to_string(),
        }),
        linuxfoundation: None,
    }
}

fn sample_linuxfoundation_user_provider() -> UserProvider {
    UserProvider {
        github: None,
        linuxfoundation: Some(LinuxFoundationUserProvider {
            username: "test-user-lf".to_string(),

            issuer: Some("https://issuer.example.com".to_string()),
            subject: Some("auth0|test-user".to_string()),
        }),
    }
}

fn sample_linuxfoundation_username_only_user_provider(username: &str) -> UserProvider {
    UserProvider {
        github: None,
        linuxfoundation: Some(LinuxFoundationUserProvider {
            username: username.to_string(),

            issuer: None,
            subject: None,
        }),
    }
}

/// Starts a local axum server that captures one token exchange form body and rejects it.
async fn spawn_token_capture_server() -> (String, oneshot::Receiver<HashMap<String, String>>) {
    // Bind an ephemeral listener and prepare the capture channel
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("token capture listener to bind");
    let addr = listener
        .local_addr()
        .expect("token capture listener address to exist");
    let (body_tx, body_rx) = oneshot::channel();
    let body_tx = Arc::new(Mutex::new(Some(body_tx)));

    // Serve a fake token endpoint that records the form parameters and replies invalid_grant
    let router = Router::new().route(
        "/token",
        post(move |Form(params): Form<HashMap<String, String>>| {
            let body_tx = Arc::clone(&body_tx);
            async move {
                if let Some(tx) = body_tx.lock().expect("capture mutex poisoned").take() {
                    let _ = tx.send(params);
                }
                (
                    StatusCode::BAD_REQUEST,
                    Json(json!({ "error": "invalid_grant" })),
                )
            }
        }),
    );
    tokio::spawn(async move {
        axum::serve(listener, router)
            .await
            .expect("token capture server to serve");
    });

    (format!("http://{addr}/token"), body_rx)
}
