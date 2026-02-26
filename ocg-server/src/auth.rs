//! This module contains authentication and authorization logic for the server.

use std::{collections::HashMap, sync::Arc};

use anyhow::{Result, anyhow, bail};
use async_trait::async_trait;
use axum::http::header::{AUTHORIZATION, USER_AGENT};
use axum_login::{
    AuthManagerLayer, AuthManagerLayerBuilder,
    tower_sessions::{self, session, session_store},
};
use garde::Validate;
use oauth2::{TokenResponse, reqwest as oauth2_reqwest};
use openidconnect::{self as oidc, LocalizedClaim};
use password_auth::verify_password;
use reqwest::header::HeaderMap;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use time::Duration;
use tower_sessions::{Expiry, SessionManagerLayer, cookie::SameSite};
use uuid::Uuid;

use crate::{
    config::{HttpServerConfig, OAuth2Config, OAuth2Provider, OidcConfig, OidcProvider},
    db::DynDB,
    validation::{
        MAX_LEN_DISPLAY_NAME, MAX_LEN_S, MIN_PASSWORD_LEN, trimmed_non_empty, trimmed_non_empty_opt,
    },
};

/// Type alias for the authentication layer used in the router.
pub(crate) type AuthLayer = AuthManagerLayer<AuthnBackend, SessionStore>;

/// Setup router authentication/authorization layer.
pub(crate) async fn setup_layer(cfg: &HttpServerConfig, db: DynDB) -> Result<AuthLayer> {
    // Setup session layer
    let session_store = SessionStore::new(db.clone());
    let secure = if let Some(cookie) = &cfg.cookie {
        cookie.secure.unwrap_or(true)
    } else {
        true
    };
    let session_layer = SessionManagerLayer::new(session_store)
        .with_expiry(Expiry::OnInactivity(Duration::days(7)))
        .with_http_only(true)
        .with_same_site(SameSite::Lax)
        .with_secure(secure);

    // Setup auth layer
    let authn_backend = AuthnBackend::new(db, &cfg.oauth2, &cfg.oidc).await?;
    let auth_layer = AuthManagerLayerBuilder::new(authn_backend, session_layer).build();

    Ok(auth_layer)
}

// Session store.

/// Store for managing user sessions in the database.
#[derive(Clone)]
pub(crate) struct SessionStore {
    db: DynDB,
}

impl SessionStore {
    /// Create a new `SessionStore` with the given database handle.
    pub fn new(db: DynDB) -> Self {
        Self { db }
    }

    /// Convert an `anyhow::Error` to a session store error.
    #[allow(clippy::needless_pass_by_value)]
    fn to_session_store_error(err: anyhow::Error) -> session_store::Error {
        session_store::Error::Backend(err.to_string())
    }
}

#[async_trait]
impl tower_sessions::SessionStore for SessionStore {
    /// Create a new session record in the database.
    async fn create(&self, record: &mut session::Record) -> session_store::Result<()> {
        self.db
            .create_session(record)
            .await
            .map_err(Self::to_session_store_error)
    }

    /// Save (update) a session record in the database.
    async fn save(&self, record: &session::Record) -> session_store::Result<()> {
        self.db
            .update_session(record)
            .await
            .map_err(Self::to_session_store_error)
    }

    /// Load a session record by session ID from the database.
    async fn load(&self, session_id: &session::Id) -> session_store::Result<Option<session::Record>> {
        self.db
            .get_session(session_id)
            .await
            .map_err(Self::to_session_store_error)
    }

    /// Delete a session record by session ID from the database.
    async fn delete(&self, session_id: &session::Id) -> session_store::Result<()> {
        self.db
            .delete_session(session_id)
            .await
            .map_err(Self::to_session_store_error)
    }
}

impl std::fmt::Debug for SessionStore {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SessionStore").finish_non_exhaustive()
    }
}

// Authentication backend.

/// Backend for authenticating users via `OAuth2`, `Oidc`, or password.
#[derive(Clone)]
pub(crate) struct AuthnBackend {
    /// Database handle.
    db: DynDB,
    /// HTTP client for making requests to `OAuth2` and `Oidc` providers.
    http_client: oauth2_reqwest::Client,
    /// Registered `OAuth2` providers.
    pub oauth2_providers: OAuth2Providers,
    /// Registered `Oidc` providers.
    pub oidc_providers: OidcProviders,
}

impl AuthnBackend {
    /// Create a new `AuthnBackend` instance.
    #[allow(unused_mut)]
    pub async fn new(db: DynDB, oauth2_cfg: &OAuth2Config, oidc_cfg: &OidcConfig) -> Result<Self> {
        let mut builder =
            oauth2_reqwest::ClientBuilder::new().redirect(oauth2_reqwest::redirect::Policy::none());
        #[cfg(test)]
        {
            // macOS sandbox testing workaround
            builder = builder.no_proxy();
        }
        let http_client = builder.build()?;
        let oauth2_providers = Self::setup_oauth2_providers(oauth2_cfg)?;
        let oidc_providers = Self::setup_oidc_providers(oidc_cfg, http_client.clone()).await?;

        Ok(Self {
            db,
            http_client,
            oauth2_providers,
            oidc_providers,
        })
    }

    /// Authenticate a user using `OAuth2` credentials.
    async fn authenticate_oauth2(&self, creds: OAuth2Credentials) -> Result<Option<User>> {
        // Exchange the authorization code for an access token
        let Some(oauth2_provider) = self.oauth2_providers.get(&creds.provider) else {
            bail!("oauth2 provider not found")
        };
        let access_token = oauth2_provider
            .client
            .exchange_code(oauth2::AuthorizationCode::new(creds.code))
            .request_async(&self.http_client)
            .await?
            .access_token()
            .secret()
            .clone();

        // Get the user if they exist, otherwise sign them up
        let user_summary = match creds.provider {
            OAuth2Provider::GitHub => UserSummary::from_github_profile(&access_token).await?,
        };
        let user = if let Some(user) = self.db.get_user_by_email(&user_summary.email).await? {
            user
        } else {
            let (user, _) = self.db.sign_up_user(&user_summary, true).await?;
            user
        };

        Ok(Some(user))
    }

    /// Authenticate a user using `Oidc` credentials.
    async fn authenticate_oidc(&self, creds: OidcCredentials) -> Result<Option<User>> {
        // Exchange the authorization code for an access and id token
        let Some(oidc_provider) = self.oidc_providers.get(&creds.provider) else {
            bail!("oidc provider not found")
        };
        let token_response = oidc_provider
            .client
            .exchange_code(oidc::AuthorizationCode::new(creds.code))?
            .request_async(&self.http_client)
            .await?;

        // Extract and verify ID token claims.
        let id_token_verifier = oidc_provider.client.id_token_verifier();
        let Some(id_token) = token_response.extra_fields().id_token() else {
            bail!("id token missing")
        };
        let claims = id_token.claims(&id_token_verifier, &creds.nonce)?;

        // Get the user if they exist, otherwise sign them up
        let user_summary = match creds.provider {
            OidcProvider::LinuxFoundation => UserSummary::from_oidc_id_token_claims(claims)?,
        };
        let user = if let Some(user) = self.db.get_user_by_email(&user_summary.email).await? {
            user
        } else {
            let (user, _) = self.db.sign_up_user(&user_summary, true).await?;
            user
        };

        Ok(Some(user))
    }

    /// Authenticate user using password credentials.
    async fn authenticate_password(&self, creds: PasswordCredentials) -> Result<Option<User>> {
        // Get user from database
        let user = self.db.get_user_by_username(&creds.username).await?;

        // Check if the credentials are valid, returning the user if they are
        if let Some(mut user) = user {
            // Check if the user's password is set
            let Some(password_hash) = user.password.clone() else {
                return Ok(None);
            };

            // Verify the password
            if tokio::task::spawn_blocking(move || verify_password(creds.password, &password_hash))
                .await?
                .is_ok()
            {
                user.password = None;
                return Ok(Some(user));
            }
        }

        Ok(None)
    }

    /// Set up `OAuth2` providers from configuration.
    fn setup_oauth2_providers(oauth2_cfg: &OAuth2Config) -> Result<OAuth2Providers> {
        let mut providers: OAuth2Providers = HashMap::new();

        for (provider, cfg) in oauth2_cfg {
            let client = oauth2::basic::BasicClient::new(oauth2::ClientId::new(cfg.client_id.clone()))
                .set_client_secret(oauth2::ClientSecret::new(cfg.client_secret.clone()))
                .set_auth_uri(oauth2::AuthUrl::new(cfg.auth_url.clone())?)
                .set_token_uri(oauth2::TokenUrl::new(cfg.token_url.clone())?)
                .set_redirect_uri(oauth2::RedirectUrl::new(cfg.redirect_uri.clone())?);

            providers.insert(
                provider.clone(),
                Arc::new(OAuth2ProviderDetails {
                    client,
                    scopes: cfg.scopes.clone(),
                }),
            );
        }

        Ok(providers)
    }

    /// Set up `Oidc` providers from configuration.
    async fn setup_oidc_providers(
        oidc_cfg: &OidcConfig,
        http_client: oauth2_reqwest::Client,
    ) -> Result<OidcProviders> {
        let mut providers: OidcProviders = HashMap::new();

        for (provider, cfg) in oidc_cfg {
            let issuer_url = oidc::IssuerUrl::new(cfg.issuer_url.clone())?;
            let client = oidc::core::CoreClient::from_provider_metadata(
                oidc::core::CoreProviderMetadata::discover_async(issuer_url, &http_client).await?,
                oidc::ClientId::new(cfg.client_id.clone()),
                Some(oidc::ClientSecret::new(cfg.client_secret.clone())),
            )
            .set_redirect_uri(oidc::RedirectUrl::new(cfg.redirect_uri.clone())?);

            providers.insert(
                provider.clone(),
                Arc::new(OidcProviderDetails {
                    client,
                    scopes: cfg.scopes.clone(),
                }),
            );
        }

        Ok(providers)
    }
}

impl axum_login::AuthnBackend for AuthnBackend {
    type User = User;
    type Credentials = Credentials;
    type Error = AuthError;

    /// Authenticate a user using the provided credentials.
    async fn authenticate(&self, creds: Self::Credentials) -> Result<Option<Self::User>, Self::Error> {
        match creds {
            Credentials::OAuth2(creds) => self.authenticate_oauth2(creds).await.map_err(AuthError),
            Credentials::Oidc(creds) => self.authenticate_oidc(creds).await.map_err(AuthError),
            Credentials::Password(creds) => self.authenticate_password(creds).await.map_err(AuthError),
        }
    }

    /// Retrieve a user by user ID from the database.
    async fn get_user(&self, user_id: &axum_login::UserId<Self>) -> Result<Option<Self::User>, Self::Error> {
        self.db.get_user_by_id(user_id).await.map_err(AuthError)
    }
}

/// Type alias for an authentication session using our backend.
pub(crate) type AuthSession = axum_login::AuthSession<AuthnBackend>;

/// Type alias for a map of `OAuth2` providers.
pub(crate) type OAuth2Providers = HashMap<OAuth2Provider, Arc<OAuth2ProviderDetails>>;

/// Details for an `OAuth2` provider, including client and scopes.
#[derive(Clone)]
pub(crate) struct OAuth2ProviderDetails {
    /// `OAuth2` client for this provider.
    pub client: oauth2::basic::BasicClient<
        oauth2::EndpointSet,
        oauth2::EndpointNotSet,
        oauth2::EndpointNotSet,
        oauth2::EndpointNotSet,
        oauth2::EndpointSet,
    >,
    /// Scopes requested from the provider.
    pub scopes: Vec<String>,
}

/// Type alias for a map of `Oidc` providers.
pub(crate) type OidcProviders = HashMap<OidcProvider, Arc<OidcProviderDetails>>;

/// Details for an `Oidc` provider, including client and scopes.
#[derive(Clone)]
pub(crate) struct OidcProviderDetails {
    /// `Oidc` client for this provider.
    pub client: oidc::core::CoreClient<
        oidc::EndpointSet,
        oidc::EndpointNotSet,
        oidc::EndpointNotSet,
        oidc::EndpointNotSet,
        oidc::EndpointMaybeSet,
        oidc::EndpointMaybeSet,
    >,
    /// Scopes requested from the provider.
    pub scopes: Vec<String>,
}

/// Wrapper for authentication errors, based on `anyhow::Error`.
#[derive(thiserror::Error, Debug)]
#[error(transparent)]
pub(crate) struct AuthError(#[from] anyhow::Error);

/// Credentials for authenticating a user.
#[derive(Clone, Serialize, Deserialize)]
pub enum Credentials {
    /// `OAuth2` credentials.
    OAuth2(OAuth2Credentials),
    /// `Oidc` credentials.
    Oidc(OidcCredentials),
    /// Username and password credentials.
    Password(PasswordCredentials),
}

/// Credentials for `OAuth2` authentication.
#[derive(Clone, Serialize, Deserialize)]
pub(crate) struct OAuth2Credentials {
    /// Authorization code from the `OAuth2` provider.
    pub code: String,
    /// The `OAuth2` provider to use.
    pub provider: OAuth2Provider,
}

/// Credentials for `Oidc` authentication.
#[derive(Clone, Serialize, Deserialize)]
pub(crate) struct OidcCredentials {
    /// Authorization code from the `Oidc` provider.
    pub code: String,
    /// Nonce used for ID token verification.
    pub nonce: oidc::Nonce,
    /// The `Oidc` provider to use.
    pub provider: OidcProvider,
}

/// Credentials for password authentication.
#[derive(Clone, Serialize, Deserialize)]
pub(crate) struct PasswordCredentials {
    /// Password for authentication.
    pub password: String,
    /// Username for authentication.
    pub username: String,
}

// User types and implementations.

/// Represents a user in the system.
#[derive(Clone, Default, Serialize, Deserialize)]
pub(crate) struct User {
    /// Unique user ID.
    pub user_id: Uuid,
    /// Authentication hash for session validation.
    pub auth_hash: String,
    /// User's email address.
    pub email: String,
    /// Whether the user's email is verified.
    pub email_verified: bool,
    /// User's display name.
    pub name: String,
    /// User's username.
    pub username: String,

    /// Whether the user belongs to any group team.
    pub belongs_to_any_group_team: Option<bool>,
    /// Whether the user belongs to their community team.
    pub belongs_to_community_team: Option<bool>,
    /// User's biography.
    pub bio: Option<String>,
    /// User's Bluesky URL.
    pub bluesky_url: Option<String>,
    /// User's city.
    pub city: Option<String>,
    /// User's company.
    pub company: Option<String>,
    /// User's country.
    pub country: Option<String>,
    /// User's Facebook URL.
    pub facebook_url: Option<String>,
    /// Whether the user has a password set.
    pub has_password: Option<bool>,
    /// User's interests.
    pub interests: Option<Vec<String>>,
    /// User's `LinkedIn` URL.
    pub linkedin_url: Option<String>,
    /// User's password hash (if present).
    pub password: Option<String>,
    /// User's photo URL.
    pub photo_url: Option<String>,
    /// User's timezone.
    pub timezone: Option<String>,
    /// User's title.
    pub title: Option<String>,
    /// User's Twitter URL.
    pub twitter_url: Option<String>,
    /// User's website URL.
    pub website_url: Option<String>,
}

impl axum_login::AuthUser for User {
    type Id = Uuid;

    /// Get the user's unique ID.
    fn id(&self) -> Self::Id {
        self.user_id
    }

    /// Get the session authentication hash.
    fn session_auth_hash(&self) -> &[u8] {
        self.auth_hash.as_bytes()
    }
}

impl std::fmt::Debug for User {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("User")
            .field("user_id", &self.user_id)
            .field("username", &self.username)
            .finish_non_exhaustive()
    }
}

/// Summary of user information.
#[skip_serializing_none]
#[derive(Clone, Serialize, Deserialize, Validate)]
pub(crate) struct UserSummary {
    /// User's email address.
    #[garde(email)]
    pub email: String,
    /// User's display name.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_DISPLAY_NAME))]
    pub name: String,
    /// User's username.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_S))]
    pub username: String,

    /// Whether the user has a password set.
    #[garde(skip)]
    pub has_password: Option<bool>,
    /// User's password (if present).
    #[garde(custom(trimmed_non_empty_opt), length(min = MIN_PASSWORD_LEN, max = MAX_LEN_S))]
    pub password: Option<String>,
}

impl UserSummary {
    /// Create a `UserSummary` instance from a GitHub profile.
    async fn from_github_profile(access_token: &str) -> Result<Self> {
        // Setup headers for GitHub API requests.
        let mut headers = HeaderMap::new();
        headers.insert(USER_AGENT, "open-community-groups".parse()?);
        headers.insert(AUTHORIZATION, format!("Bearer {access_token}").as_str().parse()?);

        // Get user profile from GitHub.
        let profile = reqwest::Client::new()
            .get("https://api.github.com/user")
            .headers(headers.clone())
            .send()
            .await?
            .json::<GitHubProfile>()
            .await?;

        // Get user emails from GitHub.
        let emails = reqwest::Client::new()
            .get("https://api.github.com/user/emails")
            .headers(headers)
            .send()
            .await?
            .json::<Vec<GitHubUserEmail>>()
            .await?;

        // Get primary, verified email.
        let email = emails
            .into_iter()
            .find(|email| email.primary && email.verified)
            .ok_or_else(|| anyhow!("no valid email found (primary email must be verified)"))?;

        Ok(Self {
            email: email.email,
            name: profile.name,
            username: profile.login,
            has_password: Some(false),
            password: None,
        })
    }

    /// Create a `UserSummary` from `Oidc` Id token claims.
    fn from_oidc_id_token_claims(
        claims: &oidc::IdTokenClaims<oidc::EmptyAdditionalClaims, oidc::core::CoreGenderClaim>,
    ) -> Result<Self> {
        // Ensure email is verified and extract user info.
        if !claims.email_verified().unwrap_or(false) {
            bail!("email not verified");
        }

        let email = claims.email().ok_or_else(|| anyhow!("email missing"))?.to_string();
        let name = get_localized_claim(claims.name()).ok_or_else(|| anyhow!("name missing"))?;
        let username = get_localized_claim(claims.nickname()).ok_or_else(|| anyhow!("nickname missing"))?;

        Ok(Self {
            email,
            name: name.to_string(),
            username: username.to_string(),
            has_password: Some(false),
            password: None,
        })
    }
}

impl From<User> for UserSummary {
    /// Convert a `User` into a `UserSummary`.
    fn from(user: User) -> Self {
        Self {
            email: user.email,
            name: user.name,
            username: user.username,
            has_password: user.has_password,
            password: None,
        }
    }
}

impl std::fmt::Debug for UserSummary {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("UserSummary")
            .field("email", &self.email)
            .field("name", &self.name)
            .field("username", &self.username)
            .finish_non_exhaustive()
    }
}

/// Get the first value from a localized claim, if present.
fn get_localized_claim<T>(claim: Option<&LocalizedClaim<T>>) -> Option<T>
where
    T: Clone,
{
    claim.and_then(|v| {
        if let Some((_, v)) = v.iter().next() {
            Some((*v).clone())
        } else {
            None
        }
    })
}

/// GitHub user profile information.
#[derive(Debug, Deserialize)]
struct GitHubProfile {
    /// GitHub username.
    login: String,
    /// GitHub display name.
    name: String,
}

/// GitHub user email information.
#[derive(Debug, Deserialize)]
struct GitHubUserEmail {
    /// Email address.
    email: String,
    /// Whether this is the primary email.
    primary: bool,
    /// Whether this email is verified.
    verified: bool,
}

#[cfg(test)]
mod tests {
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
            username: "test-user".to_string(),
            ..User::default()
        }
    }
}
