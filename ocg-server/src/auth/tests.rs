use std::{collections::HashMap, sync::Arc};

use anyhow::anyhow;
use axum_login::AuthUser;
use chrono::{Duration as ChronoDuration, Utc};
use oauth2::reqwest as oauth2_reqwest;
use openidconnect as oidc;
use password_auth::generate_hash;
use uuid::Uuid;

use crate::{
    config::{
        OAuth2Config, OAuth2Provider, OAuth2ProviderConfig, OidcConfig, OidcProvider, OidcProviderConfig,
    },
    db::{DynDB, mock::MockDB},
    types::user::{GitHubUserProvider, LinuxFoundationUserProvider, UserProvider},
};

use super::*;

#[tokio::test]
async fn authenticate_dispatches_password_credentials() {
    // Setup database mock
    let password_hash = generate_hash("correct-password");
    let mut db = MockDB::new();
    db.expect_get_user_by_username()
        .times(1)
        .withf(|username| username == "test-user")
        .returning(move |_| {
            let mut user = sample_user();
            user.password = Some(password_hash.clone());
            Ok(Some(user))
        });
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

    // Check result
    assert!(user.password.is_none());
    assert_eq!(user.username, "test-user");
}

#[tokio::test]
async fn authenticate_maps_password_backend_error_to_auth_error() {
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
async fn authenticate_maps_oauth2_backend_error_to_auth_error() {
    // Setup backend without configured providers
    let db: DynDB = Arc::new(MockDB::new());
    let backend = authn_backend(db).await;

    // Execute authentication
    let result = axum_login::AuthnBackend::authenticate(
        &backend,
        Credentials::OAuth2(OAuth2Credentials {
            code: "code".to_string(),
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
async fn authenticate_maps_oidc_backend_error_to_auth_error() {
    // Setup backend without configured providers
    let db: DynDB = Arc::new(MockDB::new());
    let backend = authn_backend(db).await;

    // Execute authentication
    let result = axum_login::AuthnBackend::authenticate(
        &backend,
        Credentials::Oidc(OidcCredentials {
            code: "code".to_string(),
            nonce: oidc::Nonce::new("nonce".to_string()),
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
async fn authenticate_oauth2_returns_error_when_provider_missing() {
    // Setup backend without configured providers
    let db: DynDB = Arc::new(MockDB::new());
    let backend = authn_backend(db).await;

    // Execute authentication
    let result = backend
        .authenticate_oauth2(OAuth2Credentials {
            code: "code".to_string(),
            provider: OAuth2Provider::GitHub,
        })
        .await;

    // Check result
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("oauth2 provider not found"));
}

#[tokio::test]
async fn authenticate_oidc_returns_error_when_provider_missing() {
    // Setup backend without configured providers
    let db: DynDB = Arc::new(MockDB::new());
    let backend = authn_backend(db).await;

    // Execute authentication
    let result = backend
        .authenticate_oidc(OidcCredentials {
            code: "code".to_string(),
            nonce: oidc::Nonce::new("nonce".to_string()),
            provider: OidcProvider::LinuxFoundation,
        })
        .await;

    // Check result
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("oidc provider not found"));
}

#[tokio::test]
async fn authenticate_password_returns_none_when_password_is_incorrect() {
    // Setup database mock
    let password_hash = generate_hash("correct-password");
    let mut db = MockDB::new();
    db.expect_get_user_by_username()
        .times(1)
        .withf(|username| username == "test-user")
        .returning(move |_| {
            let mut user = sample_user();
            user.password = Some(password_hash.clone());
            Ok(Some(user))
        });
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
async fn authenticate_password_returns_none_when_password_is_missing() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_user_by_username()
        .times(1)
        .withf(|username| username == "test-user")
        .returning(|_| {
            let mut user = sample_user();
            user.password = None;
            Ok(Some(user))
        });
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
async fn authenticate_password_returns_none_when_user_not_found() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_user_by_username()
        .times(1)
        .withf(|username| username == "test-user")
        .returning(|_| Ok(None));
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
async fn authenticate_password_returns_user_without_password_when_valid() {
    // Setup database mock
    let password_hash = generate_hash("correct-password");
    let mut db = MockDB::new();
    db.expect_get_user_by_username()
        .times(1)
        .withf(|username| username == "test-user")
        .returning(move |_| {
            let mut user = sample_user();
            user.password = Some(password_hash.clone());
            Ok(Some(user))
        });
    let db: DynDB = Arc::new(db);

    // Execute authentication
    let backend = authn_backend(db).await;
    let user = backend
        .authenticate_password(PasswordCredentials {
            password: "correct-password".to_string(),
            username: "test-user".to_string(),
        })
        .await
        .unwrap()
        .unwrap();

    // Check result
    assert!(user.password.is_none());
    assert_eq!(user.email, "user@example.com");
}

#[test]
fn from_user_to_user_summary_drops_password() {
    // Setup input user
    let mut user = sample_user();
    user.has_password = Some(true);
    user.password = Some("super-secret-password".to_string());

    // Execute conversion
    let summary = UserSummary::from(user);

    // Check result
    assert!(summary.has_password.unwrap());
    assert!(summary.password.is_none());
    assert_eq!(summary.provider, Some(sample_user_provider()));
}

#[tokio::test]
async fn get_or_sign_up_external_user_merges_provider_into_existing_user() {
    // Setup database mock
    let mut db = MockDB::new();
    let existing_user = sample_user();
    let existing_user_id = existing_user.user_id;
    let incoming_provider = sample_linuxfoundation_user_provider();
    let user_summary = sample_external_user_summary(Some(incoming_provider.clone()));

    db.expect_get_user_by_email()
        .times(1)
        .withf(|email| email == "user@example.com")
        .returning(move |_| Ok(Some(existing_user.clone())));
    db.expect_update_user_provider()
        .times(1)
        .withf(move |user_id, provider| *user_id == existing_user_id && provider == &incoming_provider)
        .returning(|_, _| Ok(()));
    db.expect_sign_up_user().times(0);
    let db: DynDB = Arc::new(db);

    // Execute helper
    let backend = authn_backend(db).await;
    let user = backend.get_or_sign_up_external_user(&user_summary).await.unwrap();

    // Check result
    assert_eq!(
        user.provider,
        Some(UserProvider {
            github: Some(GitHubUserProvider {
                username: "test-user-gh".to_string(),
            }),
            linuxfoundation: Some(LinuxFoundationUserProvider {
                username: "test-user-lf".to_string(),
            }),
        })
    );
}

#[tokio::test]
async fn get_or_sign_up_external_user_sets_provider_for_existing_user_without_provider() {
    // Setup database mock
    let mut db = MockDB::new();
    let existing_user = sample_user_without_provider();
    let existing_user_id = existing_user.user_id;
    let incoming_provider = sample_user_provider();
    let user_summary = sample_external_user_summary(Some(incoming_provider.clone()));

    db.expect_get_user_by_email()
        .times(1)
        .withf(|email| email == "user@example.com")
        .returning(move |_| Ok(Some(existing_user.clone())));
    db.expect_update_user_provider()
        .times(1)
        .withf(move |user_id, provider| *user_id == existing_user_id && provider == &incoming_provider)
        .returning(|_, _| Ok(()));
    db.expect_sign_up_user().times(0);
    let db: DynDB = Arc::new(db);

    // Execute helper
    let backend = authn_backend(db).await;
    let user = backend.get_or_sign_up_external_user(&user_summary).await.unwrap();

    // Check result
    assert_eq!(user.provider, Some(sample_user_provider()));
}

#[tokio::test]
async fn get_or_sign_up_external_user_skips_provider_update_when_unchanged() {
    // Setup database mock
    let mut db = MockDB::new();
    let existing_user = sample_user();
    let user_summary = sample_external_user_summary(Some(sample_user_provider()));

    db.expect_get_user_by_email()
        .times(1)
        .withf(|email| email == "user@example.com")
        .returning(move |_| Ok(Some(existing_user.clone())));
    db.expect_update_user_provider().times(0);
    db.expect_sign_up_user().times(0);
    let db: DynDB = Arc::new(db);

    // Execute helper
    let backend = authn_backend(db).await;
    let user = backend.get_or_sign_up_external_user(&user_summary).await.unwrap();

    // Check result
    assert_eq!(user.provider, Some(sample_user_provider()));
}

#[tokio::test]
async fn get_or_sign_up_external_user_signs_up_new_user() {
    // Setup database mock
    let mut db = MockDB::new();
    let provider = sample_user_provider();
    let user_summary = sample_external_user_summary(Some(provider.clone()));
    let signed_up_user = sample_user();

    db.expect_get_user_by_email()
        .times(1)
        .withf(|email| email == "user@example.com")
        .returning(|_| Ok(None));
    db.expect_update_user_provider().times(0);
    db.expect_sign_up_user()
        .times(1)
        .withf(move |summary, email_verified| {
            summary.email == "user@example.com"
                && summary.name == "Test User"
                && summary.provider == Some(provider.clone())
                && summary.username == "test-user"
                && *email_verified
        })
        .returning(move |_, _| Ok((signed_up_user.clone(), None)));
    let db: DynDB = Arc::new(db);

    // Execute helper
    let backend = authn_backend(db).await;
    let user = backend.get_or_sign_up_external_user(&user_summary).await.unwrap();

    // Check result
    assert_eq!(user.provider, Some(sample_user_provider()));
}

#[tokio::test]
async fn get_or_sign_up_external_user_skips_provider_update_when_missing() {
    // Setup database mock
    let mut db = MockDB::new();
    let existing_user = sample_user();
    let user_summary = sample_external_user_summary(None);

    db.expect_get_user_by_email()
        .times(1)
        .withf(|email| email == "user@example.com")
        .returning(move |_| Ok(Some(existing_user.clone())));
    db.expect_update_user_provider().times(0);
    db.expect_sign_up_user().times(0);
    let db: DynDB = Arc::new(db);

    // Execute helper
    let backend = authn_backend(db).await;
    let user = backend.get_or_sign_up_external_user(&user_summary).await.unwrap();

    // Check result
    assert_eq!(user.provider, Some(sample_user_provider()));
}

#[tokio::test]
async fn get_user_maps_db_error_to_auth_error() {
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
async fn get_user_returns_none_when_user_not_found() {
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
async fn setup_oidc_providers_rejects_invalid_issuer_url() {
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
fn setup_oauth2_providers_builds_provider_map_when_config_is_valid() {
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
fn setup_oauth2_providers_rejects_invalid_auth_url() {
    // Setup invalid OAuth2 configuration
    let mut oauth2_cfg: OAuth2Config = HashMap::new();
    let mut provider_cfg = sample_oauth2_provider_config();
    provider_cfg.auth_url = "invalid-url".to_string();
    oauth2_cfg.insert(OAuth2Provider::GitHub, provider_cfg);

    // Execute provider setup
    let result = AuthnBackend::setup_oauth2_providers(&oauth2_cfg);

    // Check result
    assert!(result.is_err());
}

#[test]
fn setup_oauth2_providers_rejects_invalid_redirect_uri() {
    // Setup invalid OAuth2 configuration
    let mut oauth2_cfg: OAuth2Config = HashMap::new();
    let mut provider_cfg = sample_oauth2_provider_config();
    provider_cfg.redirect_uri = "invalid-url".to_string();
    oauth2_cfg.insert(OAuth2Provider::GitHub, provider_cfg);

    // Execute provider setup
    let result = AuthnBackend::setup_oauth2_providers(&oauth2_cfg);

    // Check result
    assert!(result.is_err());
}

#[test]
fn setup_oauth2_providers_rejects_invalid_token_url() {
    // Setup invalid OAuth2 configuration
    let mut oauth2_cfg: OAuth2Config = HashMap::new();
    let mut provider_cfg = sample_oauth2_provider_config();
    provider_cfg.token_url = "invalid-url".to_string();
    oauth2_cfg.insert(OAuth2Provider::GitHub, provider_cfg);

    // Execute provider setup
    let result = AuthnBackend::setup_oauth2_providers(&oauth2_cfg);

    // Check result
    assert!(result.is_err());
}

#[test]
fn user_debug_does_not_expose_sensitive_fields() {
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
fn user_summary_debug_does_not_expose_password() {
    // Setup input summary
    let summary = UserSummary {
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
    assert!(output.contains("UserSummary"));
    assert!(!output.contains("private-password-hash"));
}

#[test]
fn user_summary_from_oidc_id_token_claims_extracts_verified_user() {
    // Setup valid claims
    let claims = sample_oidc_claims(
        Some("user@example.com"),
        Some(true),
        Some("Test User"),
        Some("test-user"),
    );

    // Execute conversion
    let result = UserSummary::from_oidc_id_token_claims(&claims).unwrap();

    // Check result
    assert_eq!(result.email, "user@example.com");
    assert_eq!(result.name, "Test User");
    assert_eq!(
        result.provider,
        Some(UserProvider {
            github: None,
            linuxfoundation: Some(LinuxFoundationUserProvider {
                username: "test-user".to_string(),
            }),
        })
    );
    assert_eq!(result.username, "test-user");
    assert_eq!(result.has_password, Some(false));
    assert!(result.password.is_none());
}

#[test]
fn user_summary_from_oidc_id_token_claims_rejects_missing_email() {
    // Setup invalid claims
    let claims = sample_oidc_claims(None, Some(true), Some("Test User"), Some("test-user"));

    // Execute conversion
    let result = UserSummary::from_oidc_id_token_claims(&claims);

    // Check result
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("email missing"));
}

#[test]
fn user_summary_from_oidc_id_token_claims_rejects_missing_name() {
    // Setup invalid claims
    let claims = sample_oidc_claims(Some("user@example.com"), Some(true), None, Some("test-user"));

    // Execute conversion
    let result = UserSummary::from_oidc_id_token_claims(&claims);

    // Check result
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("name missing"));
}

#[test]
fn user_summary_from_oidc_id_token_claims_rejects_missing_nickname() {
    // Setup invalid claims
    let claims = sample_oidc_claims(Some("user@example.com"), Some(true), Some("Test User"), None);

    // Execute conversion
    let result = UserSummary::from_oidc_id_token_claims(&claims);

    // Check result
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("nickname missing"));
}

#[test]
fn user_summary_from_oidc_id_token_claims_rejects_missing_email_verified() {
    // Setup invalid claims
    let claims = sample_oidc_claims(
        Some("user@example.com"),
        None,
        Some("Test User"),
        Some("test-user"),
    );

    // Execute conversion
    let result = UserSummary::from_oidc_id_token_claims(&claims);

    // Check result
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("email not verified"));
}

#[test]
fn user_summary_from_oidc_id_token_claims_rejects_unverified_email() {
    // Setup invalid claims
    let claims = sample_oidc_claims(
        Some("user@example.com"),
        Some(false),
        Some("Test User"),
        Some("test-user"),
    );

    // Execute conversion
    let result = UserSummary::from_oidc_id_token_claims(&claims);

    // Check result
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("email not verified"));
}

#[test]
fn user_session_auth_hash_matches_auth_hash_bytes() {
    // Setup input user
    let mut user = sample_user();
    user.auth_hash = "private-auth-hash".to_string();

    // Execute auth hash retrieval
    let hash = user.session_auth_hash();

    // Check result
    assert_eq!(hash, user.auth_hash.as_bytes());
}

// Helpers.

async fn authn_backend(db: DynDB) -> AuthnBackend {
    let oidc_cfg: OidcConfig = HashMap::new();
    let oauth2_cfg: OAuth2Config = HashMap::new();
    AuthnBackend::new(db, &oauth2_cfg, &oidc_cfg).await.unwrap()
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
    standard_claims = standard_claims
        .set_name(name.map(|value| LocalizedClaim::from(oidc::EndUserName::new(value.to_string()))));
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
        scopes: vec!["openid".to_string(), "email".to_string(), "profile".to_string()],
    }
}

fn sample_user() -> User {
    User {
        user_id: Uuid::new_v4(),
        auth_hash: "session-auth-hash".to_string(),
        email: "user@example.com".to_string(),
        email_verified: true,
        name: "Test User".to_string(),
        optional_notifications_enabled: true,
        provider: Some(sample_user_provider()),
        username: "test-user".to_string(),
        ..User::default()
    }
}

fn sample_user_without_provider() -> User {
    User {
        provider: None,
        ..sample_user()
    }
}

fn sample_external_user_summary(provider: Option<UserProvider>) -> UserSummary {
    UserSummary {
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
        }),
    }
}
