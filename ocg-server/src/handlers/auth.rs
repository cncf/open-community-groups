//! This module defines some handlers used for authentication.

use std::collections::HashMap;

use askama::Template;
use axum::{
    extract::{Path, Query, Request, State},
    http::StatusCode,
    middleware::Next,
    response::{Html, IntoResponse, Redirect},
};
use axum_extra::extract::Form;
use axum_messages::Messages;
use openidconnect as oidc;
use password_auth::verify_password;
use percent_encoding::{NON_ALPHANUMERIC, utf8_percent_encode};
use serde::Deserialize;
use tower_sessions::Session;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    auth::{self, AuthSession, Credentials, OAuth2Credentials, OidcCredentials, PasswordCredentials},
    config::{HttpServerConfig, OAuth2Provider, OidcProvider},
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CommunityId, OAuth2, Oidc},
    },
    services::notifications::{DynNotificationsManager, NewNotification, NotificationKind},
    templates::{
        self, PageId,
        auth::{User, UserDetails},
        notifications::EmailVerification,
    },
};

/// Key used to store the authentication provider in the session.
pub(crate) const AUTH_PROVIDER_KEY: &str = "auth_provider";

/// URL for the log in page.
pub(crate) const LOG_IN_URL: &str = "/log-in";

/// URL for the log out page.
pub(crate) const LOG_OUT_URL: &str = "/log-out";

/// Key used to store the next URL in the session.
pub(crate) const NEXT_URL_KEY: &str = "next_url";

/// Key used to store the `OAuth2` CSRF state in the session.
pub(crate) const OAUTH2_CSRF_STATE_KEY: &str = "oauth2.csrf_state";

/// Key used to store the `Oidc` nonce in the session.
pub(crate) const OIDC_NONCE_KEY: &str = "oidc.nonce";

/// Key used to store the selected group ID in the session.
pub(crate) const SELECTED_GROUP_ID_KEY: &str = "selected_group_id";

/// URL for the sign up page.
pub(crate) const SIGN_UP_URL: &str = "/sign-up";

// Pages and sections handlers.

/// Handler that returns the log in page.
#[instrument(skip_all, err)]
pub(crate) async fn log_in_page(
    auth_session: AuthSession,
    messages: Messages,
    CommunityId(community_id): CommunityId,
    State(cfg): State<HttpServerConfig>,
    State(db): State<DynDB>,
    Query(query): Query<HashMap<String, String>>,
) -> Result<impl IntoResponse, HandlerError> {
    // Check if the user is already logged in
    if auth_session.user.is_some() {
        return Ok(Redirect::to("/").into_response());
    }

    // Get community information
    let community = db.get_community(community_id).await?;

    // Sanitize and encode the next url (if any)
    let next_url =
        sanitize_next_url(query.get("next_url").map(String::as_str)).map(|value| encode_next_url(&value));

    // Prepare template
    let template = templates::auth::LogInPage {
        community,
        login: cfg.login.clone(),
        messages: messages.into_iter().collect(),
        page_id: PageId::LogIn,
        path: LOG_IN_URL.to_string(),
        user: User::default(),

        next_url,
    };

    Ok(Html(template.render()?).into_response())
}

/// Handler that returns the sign up page.
#[instrument(skip_all, err)]
pub(crate) async fn sign_up_page(
    auth_session: AuthSession,
    messages: Messages,
    CommunityId(community_id): CommunityId,
    State(cfg): State<HttpServerConfig>,
    State(db): State<DynDB>,
    Query(query): Query<HashMap<String, String>>,
) -> Result<impl IntoResponse, HandlerError> {
    // Check if the user is already logged in
    if auth_session.user.is_some() {
        return Ok(Redirect::to("/").into_response());
    }

    // Get community information
    let community = db.get_community(community_id).await?;

    // Sanitize and encode the next url (if any)
    let next_url =
        sanitize_next_url(query.get("next_url").map(String::as_str)).map(|value| encode_next_url(&value));

    // Prepare template
    let template = templates::auth::SignUpPage {
        community,
        login: cfg.login.clone(),
        messages: messages.into_iter().collect(),
        page_id: PageId::SignUp,
        path: SIGN_UP_URL.to_string(),
        user: User::default(),

        next_url,
    };

    Ok(Html(template.render()?).into_response())
}

/// Handler for rendering the user menu section.
#[instrument(skip_all, err)]
pub(crate) async fn user_menu_section(auth_session: AuthSession) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let template = templates::auth::UserMenuSection {
        user: User::from_session(auth_session).await?,
    };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Handler that logs the user in.
#[instrument(skip_all)]
pub(crate) async fn log_in(
    mut auth_session: AuthSession,
    messages: Messages,
    session: Session,
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
    Query(query): Query<HashMap<String, String>>,
    Form(login_form): Form<LoginForm>,
) -> Result<impl IntoResponse, HandlerError> {
    // Sanitize next url
    let next_url = sanitize_next_url(query.get("next_url").map(String::as_str));

    // Authenticate user
    let creds = PasswordCredentials {
        community_id,
        username: login_form.username,
        password: login_form.password,
    };
    let Some(user) = auth_session
        .authenticate(Credentials::Password(creds))
        .await
        .map_err(|e| HandlerError::Auth(e.to_string()))?
    else {
        messages.error("Invalid credentials. Please make sure you have verified your email address.");
        let log_in_url = get_log_in_url(next_url.as_deref());
        return Ok(Redirect::to(&log_in_url));
    };

    // Log user in
    auth_session
        .login(&user)
        .await
        .map_err(|e| HandlerError::Auth(e.to_string()))?;

    // Use the first group as the selected group in the session
    let groups = db.list_user_groups(&user.user_id).await?;
    if !groups.is_empty() {
        session.insert(SELECTED_GROUP_ID_KEY, groups[0].group_id).await?;
    }

    let next_url = next_url.as_deref().unwrap_or("/");
    Ok(Redirect::to(next_url))
}

/// Handler that logs the user out.
#[instrument(skip_all)]
pub(crate) async fn log_out(mut auth_session: AuthSession) -> Result<impl IntoResponse, HandlerError> {
    auth_session
        .logout()
        .await
        .map_err(|e| HandlerError::Auth(e.to_string()))?;

    Ok(Redirect::to(LOG_IN_URL))
}

/// Handler that completes the oauth2 authorization process.
#[instrument(skip_all)]
pub(crate) async fn oauth2_callback(
    mut auth_session: AuthSession,
    messages: Messages,
    session: Session,
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path(provider): Path<OAuth2Provider>,
    Query(OAuth2AuthorizationResponse { code, state }): Query<OAuth2AuthorizationResponse>,
) -> Result<impl IntoResponse, HandlerError> {
    const OAUTH2_AUTHORIZATION_FAILED: &str = "OAuth2 authorization failed";

    // Verify oauth2 csrf state
    let Some(state_in_session) = session.remove::<oauth2::CsrfToken>(OAUTH2_CSRF_STATE_KEY).await? else {
        messages.error(OAUTH2_AUTHORIZATION_FAILED);
        return Ok(Redirect::to(LOG_IN_URL));
    };
    if state_in_session.secret() != state.secret() {
        messages.error(OAUTH2_AUTHORIZATION_FAILED);
        return Ok(Redirect::to(LOG_IN_URL));
    }

    // Get next url from session (if any)
    let next_url = session
        .remove::<Option<String>>(NEXT_URL_KEY)
        .await?
        .flatten()
        .and_then(|value| sanitize_next_url(Some(value.as_str())));
    let log_in_url = get_log_in_url(next_url.as_deref());

    // Authenticate user
    let creds = OAuth2Credentials {
        code,
        community_id,
        provider,
    };
    let user = match auth_session.authenticate(Credentials::OAuth2(creds)).await {
        Ok(Some(user)) => user,
        Ok(None) => {
            messages.error(OAUTH2_AUTHORIZATION_FAILED);
            return Ok(Redirect::to(&log_in_url));
        }
        Err(err) => {
            messages.error(format!("{OAUTH2_AUTHORIZATION_FAILED}: {err}"));
            return Ok(Redirect::to(&log_in_url));
        }
    };

    // Log user in
    auth_session
        .login(&user)
        .await
        .map_err(|e| HandlerError::Auth(e.to_string()))?;

    // Use the first group as the selected group in the session
    let groups = db.list_user_groups(&user.user_id).await?;
    if !groups.is_empty() {
        session.insert(SELECTED_GROUP_ID_KEY, groups[0].group_id).await?;
    }

    let next_url = next_url.as_deref().unwrap_or("/");
    Ok(Redirect::to(next_url))
}

/// Handler that redirects the user to the oauth2 provider.
#[instrument(skip_all)]
pub(crate) async fn oauth2_redirect(
    session: Session,
    OAuth2(oauth2_provider): OAuth2,
    Form(NextUrl { next_url }): Form<NextUrl>,
) -> Result<impl IntoResponse, HandlerError> {
    // Generate the authorization url
    let mut builder = oauth2_provider.client.authorize_url(oauth2::CsrfToken::new_random);
    for scope in &oauth2_provider.scopes {
        builder = builder.add_scope(oauth2::Scope::new(scope.clone()));
    }
    let (authorize_url, csrf_state) = builder.url();

    // Sanitize the next url (if provided)
    let next_url = sanitize_next_url(next_url.as_deref());

    // Save the csrf state and next url in the session
    session.insert(OAUTH2_CSRF_STATE_KEY, csrf_state.secret()).await?;
    session.insert(NEXT_URL_KEY, next_url).await?;

    // Redirect to the authorization url
    Ok(Redirect::to(authorize_url.as_str()))
}

/// Handler that completes the oidc authorization process.
#[instrument(skip_all)]
pub(crate) async fn oidc_callback(
    mut auth_session: AuthSession,
    messages: Messages,
    session: Session,
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path(provider): Path<OidcProvider>,
    Query(OAuth2AuthorizationResponse { code, state }): Query<OAuth2AuthorizationResponse>,
) -> Result<impl IntoResponse, HandlerError> {
    const OIDC_AUTHORIZATION_FAILED: &str = "OpenID Connect authorization failed";

    // Verify oauth2 csrf state
    let Some(state_in_session) = session.remove::<oauth2::CsrfToken>(OAUTH2_CSRF_STATE_KEY).await? else {
        messages.error(OIDC_AUTHORIZATION_FAILED);
        return Ok(Redirect::to(LOG_IN_URL));
    };
    if state_in_session.secret() != state.secret() {
        messages.error(OIDC_AUTHORIZATION_FAILED);
        return Ok(Redirect::to(LOG_IN_URL));
    }

    // Get oidc nonce from session
    let Some(nonce) = session.remove::<oidc::Nonce>(OIDC_NONCE_KEY).await? else {
        messages.error(OIDC_AUTHORIZATION_FAILED);
        return Ok(Redirect::to(LOG_IN_URL));
    };

    // Get next url from session (if any)
    let next_url = session
        .remove::<Option<String>>(NEXT_URL_KEY)
        .await?
        .flatten()
        .and_then(|value| sanitize_next_url(Some(value.as_str())));
    let log_in_url = get_log_in_url(next_url.as_deref());

    // Authenticate user
    let creds = OidcCredentials {
        code,
        community_id,
        nonce,
        provider: provider.clone(),
    };
    let user = match auth_session.authenticate(Credentials::Oidc(creds)).await {
        Ok(Some(user)) => user,
        Ok(None) => {
            messages.error(OIDC_AUTHORIZATION_FAILED);
            return Ok(Redirect::to(&log_in_url));
        }
        Err(err) => {
            messages.error(format!("{OIDC_AUTHORIZATION_FAILED}: {err}"));
            return Ok(Redirect::to(&log_in_url));
        }
    };

    // Log user in
    auth_session
        .login(&user)
        .await
        .map_err(|e| HandlerError::Auth(e.to_string()))?;

    // Use the first group as the selected group in the session
    let groups = db.list_user_groups(&user.user_id).await?;
    if !groups.is_empty() {
        session.insert(SELECTED_GROUP_ID_KEY, groups[0].group_id).await?;
    }

    // Track auth provider in the session
    session.insert(AUTH_PROVIDER_KEY, provider).await?;

    let next_url = next_url.as_deref().unwrap_or("/");
    Ok(Redirect::to(next_url))
}

/// Handler that redirects the user to the oidc provider.
#[instrument(skip_all)]
pub(crate) async fn oidc_redirect(
    session: Session,
    Oidc(oidc_provider): Oidc,
    Form(NextUrl { next_url }): Form<NextUrl>,
) -> Result<impl IntoResponse, HandlerError> {
    // Generate the authorization url
    let mut builder = oidc_provider.client.authorize_url(
        oidc::AuthenticationFlow::<oidc::core::CoreResponseType>::AuthorizationCode,
        oidc::CsrfToken::new_random,
        oidc::Nonce::new_random,
    );
    for scope in &oidc_provider.scopes {
        builder = builder.add_scope(oidc::Scope::new(scope.clone()));
    }
    let (authorize_url, csrf_state, nonce) = builder.url();

    // Sanitize the next url (if provided)
    let next_url = sanitize_next_url(next_url.as_deref());

    // Save the csrf state, nonce and next url in the session
    session.insert(OAUTH2_CSRF_STATE_KEY, csrf_state.secret()).await?;
    session.insert(OIDC_NONCE_KEY, nonce.secret()).await?;
    session.insert(NEXT_URL_KEY, next_url).await?;

    // Redirect to the authorization url
    Ok(Redirect::to(authorize_url.as_str()))
}

/// Handler that signs up a new user.
#[instrument(skip_all)]
pub(crate) async fn sign_up(
    messages: Messages,
    CommunityId(community_id): CommunityId,
    State(cfg): State<HttpServerConfig>,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    Query(query): Query<HashMap<String, String>>,
    Form(mut user_summary): Form<auth::UserSummary>,
) -> Result<impl IntoResponse, HandlerError> {
    // Check if the password has been provided
    let Some(password) = user_summary.password.take() else {
        return Ok((StatusCode::BAD_REQUEST, "password not provided").into_response());
    };

    // Generate password hash
    user_summary.password = Some(password_auth::generate_hash(&password));

    // Sign up the user
    let Ok((user, email_verification_code)) = db.sign_up_user(&community_id, &user_summary, false).await
    else {
        // Redirect to the sign up page on error
        messages.error("Something went wrong while signing up. Please try again later.");
        return Ok(Redirect::to(SIGN_UP_URL).into_response());
    };

    // Enqueue email verification notification
    if let Some(code) = email_verification_code {
        let template_data = EmailVerification {
            link: format!(
                "{}/verify-email/{code}",
                cfg.base_url.strip_suffix('/').unwrap_or(&cfg.base_url)
            ),
        };
        let notification = NewNotification {
            kind: NotificationKind::EmailVerification,
            recipients: vec![user.user_id],
            template_data: Some(serde_json::to_value(&template_data)?),
        };
        notifications_manager.enqueue(&notification).await?;
        messages.success("Please verify your email to complete the sign up process.");
    }

    // Redirect to the log in page on success
    let next_url = sanitize_next_url(query.get("next_url").map(String::as_str));
    let log_in_url = get_log_in_url(next_url.as_deref());
    Ok(Redirect::to(&log_in_url).into_response())
}

/// Handler that updates the user's details.
#[instrument(skip_all, err)]
pub(crate) async fn update_user_details(
    auth_session: AuthSession,
    messages: Messages,
    State(db): State<DynDB>,
    State(serde_qs_de): State<serde_qs::Config>,
    body: String,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Get user details from body
    let user_data: UserDetails = match serde_qs_de.deserialize_str(&body).map_err(anyhow::Error::new) {
        Ok(data) => data,
        Err(e) => return Ok((StatusCode::UNPROCESSABLE_ENTITY, e.to_string()).into_response()),
    };

    // Update user in database
    let user_id = user.user_id;
    db.update_user_details(&user_id, &user_data).await?;
    messages.success("User details updated successfully.");

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]).into_response())
}

/// Handler that updates the user's password.
#[instrument(skip_all, err)]
pub(crate) async fn update_user_password(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    Form(mut input): Form<templates::auth::UserPassword>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.expect("user to be logged in");

    // Check if the old password provided is correct
    let Some(old_password_hash) = db.get_user_password(&user.user_id).await? else {
        return Ok(StatusCode::BAD_REQUEST.into_response());
    };
    if tokio::task::spawn_blocking(move || verify_password(&input.old_password, &old_password_hash))
        .await
        .map_err(anyhow::Error::from)?
        .is_err()
    {
        return Ok(StatusCode::FORBIDDEN.into_response());
    }

    // Update password in database
    input.new_password = password_auth::generate_hash(&input.new_password);
    db.update_user_password(&user.user_id, &input.new_password).await?;

    Ok(Redirect::to(LOG_OUT_URL).into_response())
}

/// Handler that verifies the user's email.
#[instrument(skip_all, err)]
pub(crate) async fn verify_email(
    messages: Messages,
    State(db): State<DynDB>,
    Path(code): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Verify the email
    if db.verify_email(&code).await.is_ok() {
        messages.success("Email verified successfully. You can now log in using your credentials.");
    } else {
        messages.error("Error verifying email (please note that links are only valid for 24 hours).");
    }
    Ok(Redirect::to(LOG_IN_URL))
}

// Helpers.

/// Percent-encode a `next_url` so it can be safely embedded in a query string.
fn encode_next_url(next_url: &str) -> String {
    utf8_percent_encode(next_url, NON_ALPHANUMERIC).to_string()
}

/// Get the log in url including the next url if provided.
fn get_log_in_url(next_url: Option<&str>) -> String {
    let mut log_in_url = LOG_IN_URL.to_string();
    if let Some(next_url) = sanitize_next_url(next_url) {
        log_in_url = format!("{log_in_url}?next_url={}", encode_next_url(&next_url));
    }
    log_in_url
}

/// Sanitize a `next_url` value ensuring it points to an in-site path.
fn sanitize_next_url(next_url: Option<&str>) -> Option<String> {
    let value = next_url?.trim();
    if value.is_empty() {
        return None;
    }
    if !value.starts_with('/') || value.starts_with("//") {
        return None;
    }
    Some(value.to_string())
}

// Types.

/// Login form data from the user.
#[derive(Debug, Deserialize)]
pub(crate) struct LoginForm {
    /// Username for authentication.
    pub username: String,
    /// Password for authentication.
    pub password: String,
}

// Deserialization helpers.

/// `OAuth2` authorization response containing code and CSRF state.
#[derive(Debug, Clone, Deserialize)]
pub struct OAuth2AuthorizationResponse {
    /// Authorization code returned by the `OAuth2` provider.
    code: String,
    /// CSRF state returned by the `OAuth2` provider.
    state: oauth2::CsrfToken,
}

/// Next URL to redirect to after authentication.
#[derive(Debug, Deserialize)]
pub(crate) struct NextUrl {
    /// The next URL to redirect to, if provided.
    pub next_url: Option<String>,
}

// Authorization middleware.

/// Check if the user belongs to any group's team.
#[instrument(skip_all)]
pub(crate) async fn user_belongs_to_any_group_team(
    auth_session: AuthSession,
    request: Request,
    next: Next,
) -> impl IntoResponse {
    // Check if user is logged in
    let Some(user) = auth_session.user else {
        return StatusCode::FORBIDDEN.into_response();
    };

    // Check if user belongs to any group team
    if !user.belongs_to_any_group_team.unwrap_or(false) {
        return StatusCode::FORBIDDEN.into_response();
    }

    next.run(request).await.into_response()
}

/// Check if the user owns the community.
#[instrument(skip_all)]
pub(crate) async fn user_owns_community(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    auth_session: AuthSession,
    request: Request,
    next: Next,
) -> impl IntoResponse {
    // Check if user is logged in
    let Some(user) = auth_session.user else {
        return StatusCode::FORBIDDEN.into_response();
    };

    // Check if the user owns the community
    let Ok(user_owns_community) = db.user_owns_community(&community_id, &user.user_id).await else {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    };
    if !user_owns_community {
        return StatusCode::FORBIDDEN.into_response();
    }

    next.run(request).await.into_response()
}

/// Check if the user owns the group.
#[instrument(skip_all)]
pub(crate) async fn user_owns_group(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path(group_id): Path<Uuid>,
    auth_session: AuthSession,
    request: Request,
    next: Next,
) -> impl IntoResponse {
    // Check if user is logged in
    let Some(user) = auth_session.user else {
        return StatusCode::FORBIDDEN.into_response();
    };

    // Check if the user owns the group
    let Ok(user_owns_group) = db.user_owns_group(&community_id, &group_id, &user.user_id).await else {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    };
    if !user_owns_group {
        return StatusCode::FORBIDDEN.into_response();
    }

    next.run(request).await.into_response()
}

// Tests.

#[cfg(test)]
mod tests {
    use std::{collections::HashMap, sync::Arc};

    use anyhow::anyhow;
    use axum::{
        Router,
        body::{Body, to_bytes},
        http::{
            HeaderValue, Request, StatusCode,
            header::{CACHE_CONTROL, CONTENT_TYPE, COOKIE, HOST, LOCATION},
        },
        middleware,
        response::IntoResponse,
        routing::get,
    };
    use axum_extra::extract::Form;
    use axum_login::tower_sessions::session;
    use oauth2::{AuthUrl, ClientId, ClientSecret, RedirectUrl, TokenUrl, basic::BasicClient};
    use openidconnect as oidc;
    use serde_json::json;
    use time::OffsetDateTime;
    use tower::ServiceExt;
    use tower_sessions::{MemoryStore, Session};
    use uuid::Uuid;

    use crate::{
        auth::{OAuth2ProviderDetails, OidcProviderDetails},
        config::{HttpServerConfig, LoginOptions, OAuth2Provider, OAuth2ProviderConfig},
        db::mock::MockDB,
        handlers::{
            extractors::{OAuth2, Oidc},
            tests::*,
        },
        router::State,
        services::notifications::{MockNotificationsManager, NotificationKind},
    };

    use super::*;

    #[tokio::test]
    async fn test_log_in_page_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_community()
            .times(1)
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(sample_community(community_id)));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri(LOG_IN_URL)
            .header(HOST, "example.test")
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::OK);
        assert_eq!(
            parts.headers.get(CONTENT_TYPE).unwrap(),
            &HeaderValue::from_static("text/html; charset=utf-8"),
        );
        assert_eq!(
            parts.headers.get(CACHE_CONTROL).unwrap(),
            &HeaderValue::from_static("max-age=0"),
        );
        assert!(!bytes.is_empty());
    }

    #[tokio::test]
    async fn test_log_in_page_redirects_when_authenticated() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri(LOG_IN_URL)
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::SEE_OTHER);
        assert_eq!(
            parts.headers.get(LOCATION).unwrap(),
            &HeaderValue::from_static("/"),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_sign_up_page_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_community()
            .times(1)
            .withf(move |id| *id == community_id)
            .returning(move |_| Ok(sample_community(community_id)));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri(SIGN_UP_URL)
            .header(HOST, "example.test")
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::OK);
        assert_eq!(
            parts.headers.get(CONTENT_TYPE).unwrap(),
            &HeaderValue::from_static("text/html; charset=utf-8"),
        );
        assert_eq!(
            parts.headers.get(CACHE_CONTROL).unwrap(),
            &HeaderValue::from_static("max-age=0"),
        );
        assert!(!bytes.is_empty());
    }

    #[tokio::test]
    async fn test_sign_up_page_redirects_when_authenticated() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri(SIGN_UP_URL)
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::SEE_OTHER);
        assert_eq!(
            parts.headers.get(LOCATION).unwrap(),
            &HeaderValue::from_static("/"),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_user_menu_section_success() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri("/section/user-menu")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::OK);
        assert_eq!(
            parts.headers.get(CONTENT_TYPE).unwrap(),
            &HeaderValue::from_static("text/html; charset=utf-8"),
        );
        assert_eq!(
            parts.headers.get(CACHE_CONTROL).unwrap(),
            &HeaderValue::from_static("max-age=0"),
        );
        assert!(!bytes.is_empty());
    }

    #[tokio::test]
    async fn test_log_in_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let password_hash = password_auth::generate_hash("secret-password");
        let session_record = empty_session_record(session_id);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_user_by_username()
            .times(1)
            .withf(move |cid, username| *cid == community_id && username == "test-user")
            .returning(move |_, _| {
                let mut user = sample_auth_user(user_id, &auth_hash);
                user.password = Some(password_hash.clone());
                Ok(Some(user))
            });
        db.expect_delete_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(|_| Ok(()));
        db.expect_create_session()
            .times(1)
            .withf(move |record| record_contains_selected_group(record, group_id))
            .returning(|_| Ok(()));
        db.expect_list_user_groups()
            .times(1)
            .withf(move |uid| uid == &user_id)
            .returning(move |_| Ok(vec![sample_group_summary(group_id)]));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router
        let mut cfg = HttpServerConfig::default();
        cfg.login.email = true;
        let router = setup_test_router_with_config(cfg, db, nm).await;

        // Setup request
        let request = Request::builder()
            .method("POST")
            .uri("/log-in?next_url=%2Fdashboard")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
            .body(Body::from("username=test-user&password=secret-password"))
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::SEE_OTHER);
        assert!(parts.headers.contains_key("set-cookie"));
        assert_eq!(
            parts.headers.get(LOCATION).unwrap(),
            &HeaderValue::from_static("/dashboard"),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_log_in_invalid_credentials() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let session_record = empty_session_record(session_id);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_get_user_by_username()
            .times(1)
            .withf(move |cid, username| *cid == community_id && username == "test-user")
            .returning(|_, _| Ok(None));
        db.expect_update_session()
            .times(1)
            .withf(move |record| {
                message_matches(
                    record,
                    "Invalid credentials. Please make sure you have verified your email address.",
                )
            })
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router
        let mut cfg = HttpServerConfig::default();
        cfg.login.email = true;
        let router = setup_test_router_with_config(cfg, db, nm).await;

        // Setup request
        let request = Request::builder()
            .method("POST")
            .uri("/log-in")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
            .body(Body::from("username=test-user&password=wrong"))
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::SEE_OTHER);
        assert_eq!(
            parts.headers.get(LOCATION).unwrap(),
            &HeaderValue::from_static(LOG_IN_URL),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_log_out_success() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_delete_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri(LOG_OUT_URL)
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::SEE_OTHER);
        assert_eq!(
            parts.headers.get(LOCATION).unwrap(),
            &HeaderValue::from_static(LOG_IN_URL),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_log_out_invalid_session() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(|_| Ok(None));
        db.expect_get_user_by_id().times(0);
        db.expect_delete_session().times(0);

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri(LOG_OUT_URL)
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::SEE_OTHER);
        assert_eq!(
            parts.headers.get(LOCATION).unwrap(),
            &HeaderValue::from_static(LOG_IN_URL),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_oauth2_callback_missing_state() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let session_record = empty_session_record(session_id);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_update_session()
            .times(1)
            .withf(move |record| message_matches(record, "OAuth2 authorization failed"))
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue().times(0);

        // Setup router
        let mut cfg = HttpServerConfig::default();
        cfg.login.github = true;
        cfg.oauth2.insert(
            OAuth2Provider::GitHub,
            OAuth2ProviderConfig {
                auth_url: "https://oauth.example/authorize".to_string(),
                client_id: "client-id".to_string(),
                client_secret: "client-secret".to_string(),
                redirect_uri: "https://app.example/log-in/oauth2/github/callback".to_string(),
                scopes: vec!["read:user".to_string()],
                token_url: "https://oauth.example/token".to_string(),
            },
        );
        let router = setup_test_router_with_config(cfg, db, nm).await;

        // Setup request
        let request = Request::builder()
            .method("GET")
            .uri("/log-in/oauth2/github/callback?code=test-code&state=test-state")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::SEE_OTHER);
        assert_eq!(
            parts.headers.get(LOCATION).unwrap(),
            &HeaderValue::from_static(LOG_IN_URL),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_oauth2_callback_state_mismatch() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let mut session_record = empty_session_record(session_id);
        session_record
            .data
            .insert(OAUTH2_CSRF_STATE_KEY.to_string(), json!("state-in-session"));

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_update_session()
            .times(1)
            .withf(move |record| message_matches(record, "OAuth2 authorization failed"))
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue().times(0);

        // Setup router
        let mut cfg = HttpServerConfig::default();
        cfg.login.github = true;
        cfg.oauth2.insert(
            OAuth2Provider::GitHub,
            OAuth2ProviderConfig {
                auth_url: "https://oauth.example/authorize".to_string(),
                client_id: "client-id".to_string(),
                client_secret: "client-secret".to_string(),
                redirect_uri: "https://app.example/log-in/oauth2/github/callback".to_string(),
                scopes: vec!["read:user".to_string()],
                token_url: "https://oauth.example/token".to_string(),
            },
        );
        let router = setup_test_router_with_config(cfg, db, nm).await;

        // Setup request
        let request = Request::builder()
            .method("GET")
            .uri("/log-in/oauth2/github/callback?code=test-code&state=state-in-request")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::SEE_OTHER);
        assert_eq!(
            parts.headers.get(LOCATION).unwrap(),
            &HeaderValue::from_static(LOG_IN_URL),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_oauth2_redirect_success() {
        // Setup session and form input
        let store = Arc::new(MemoryStore::default());
        let session = Session::new(None, store, None);
        let form = Form(NextUrl {
            next_url: Some("/dashboard".to_string()),
        });

        // Setup oauth2 provider details
        let client = BasicClient::new(ClientId::new("client-id".to_string()))
            .set_client_secret(ClientSecret::new("client-secret".to_string()))
            .set_auth_uri(AuthUrl::new("https://oauth.example/authorize".to_string()).unwrap())
            .set_token_uri(TokenUrl::new("https://oauth.example/token".to_string()).unwrap())
            .set_redirect_uri(
                RedirectUrl::new("https://app.example/log-in/oauth2/github/callback".to_string()).unwrap(),
            );
        let provider = OAuth2ProviderDetails {
            client,
            scopes: vec!["read:user".to_string()],
        };

        // Execute handler
        let response = oauth2_redirect(session.clone(), OAuth2(Arc::new(provider)), form)
            .await
            .expect("oauth2 redirect should succeed")
            .into_response();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();
        let location = parts.headers.get(LOCATION).unwrap().to_str().unwrap();
        let (base_url, query) = location
            .split_once('?')
            .expect("redirect url to contain query string");

        // Check response matches expectations
        let csrf_state: Option<String> = session.get(OAUTH2_CSRF_STATE_KEY).await.unwrap();
        let next_url: Option<Option<String>> = session.get(NEXT_URL_KEY).await.unwrap();
        assert_eq!(parts.status, StatusCode::SEE_OTHER);
        assert_eq!(base_url, "https://oauth.example/authorize");
        assert_eq!(
            csrf_state.as_deref(),
            query
                .split('&')
                .find_map(|pair| pair.strip_prefix("state=").map(String::from))
                .as_deref(),
        );
        assert_eq!(next_url, Some(Some("/dashboard".to_string())));
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_oidc_callback_missing_nonce() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let mut session_record = empty_session_record(session_id);
        session_record
            .data
            .insert(OAUTH2_CSRF_STATE_KEY.to_string(), json!("state-in-session"));

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_update_session()
            .times(1)
            .withf(move |record| message_matches(record, "OpenID Connect authorization failed"))
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue().times(0);

        // Setup router
        let mut cfg = HttpServerConfig::default();
        cfg.login.linuxfoundation = true;
        let router = setup_test_router_with_config(cfg, db, nm).await;

        // Setup request
        let request = Request::builder()
            .method("GET")
            .uri("/log-in/oidc/linuxfoundation/callback?code=test-code&state=state-in-session")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::SEE_OTHER);
        assert_eq!(
            parts.headers.get(LOCATION).unwrap(),
            &HeaderValue::from_static(LOG_IN_URL),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_oidc_callback_missing_state() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let session_record = empty_session_record(session_id);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_update_session()
            .times(1)
            .withf(move |record| message_matches(record, "OpenID Connect authorization failed"))
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue().times(0);

        // Setup router
        let mut cfg = HttpServerConfig::default();
        cfg.login.linuxfoundation = true;
        let router = setup_test_router_with_config(cfg, db, nm).await;

        // Setup request
        let request = Request::builder()
            .method("GET")
            .uri("/log-in/oidc/linuxfoundation/callback?code=test-code&state=test-state")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::SEE_OTHER);
        assert_eq!(
            parts.headers.get(LOCATION).unwrap(),
            &HeaderValue::from_static(LOG_IN_URL),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_oidc_callback_state_mismatch() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let mut session_record = empty_session_record(session_id);
        session_record
            .data
            .insert(OAUTH2_CSRF_STATE_KEY.to_string(), json!("state-in-session"));
        session_record
            .data
            .insert(OIDC_NONCE_KEY.to_string(), json!("nonce-in-session"));

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_update_session()
            .times(1)
            .withf(move |record| message_matches(record, "OpenID Connect authorization failed"))
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue().times(0);

        // Setup router
        let mut cfg = HttpServerConfig::default();
        cfg.login.linuxfoundation = true;
        let router = setup_test_router_with_config(cfg, db, nm).await;

        // Setup request
        let request = Request::builder()
            .method("GET")
            .uri("/log-in/oidc/linuxfoundation/callback?code=test-code&state=state-in-request")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::SEE_OTHER);
        assert_eq!(
            parts.headers.get(LOCATION).unwrap(),
            &HeaderValue::from_static(LOG_IN_URL),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_oidc_redirect_success() {
        // Setup session and form input
        let store = Arc::new(MemoryStore::default());
        let session = Session::new(None, store, None);
        let form = Form(NextUrl {
            next_url: Some("/dashboard".to_string()),
        });

        // Setup oidc provider details
        let metadata = oidc::core::CoreProviderMetadata::new(
            oidc::IssuerUrl::new("https://issuer.example".to_string()).unwrap(),
            oidc::AuthUrl::new("https://issuer.example/authorize".to_string()).unwrap(),
            oidc::JsonWebKeySetUrl::new("https://issuer.example/jwks".to_string()).unwrap(),
            vec![oidc::ResponseTypes::new(vec![oidc::core::CoreResponseType::Code])],
            vec![oidc::core::CoreSubjectIdentifierType::Public],
            vec![oidc::core::CoreJwsSigningAlgorithm::RsaSsaPkcs1V15Sha256],
            oidc::EmptyAdditionalProviderMetadata::default(),
        )
        .set_jwks(oidc::JsonWebKeySet::new(vec![]));
        let client = oidc::core::CoreClient::from_provider_metadata(
            metadata,
            oidc::ClientId::new("client-id".to_string()),
            Some(oidc::ClientSecret::new("client-secret".to_string())),
        )
        .set_redirect_uri(
            oidc::RedirectUrl::new("https://app.example/log-in/oidc/provider/callback".to_string()).unwrap(),
        );
        let provider = OidcProviderDetails {
            client,
            scopes: vec!["openid".to_string()],
        };

        // Execute handler
        let response = oidc_redirect(session.clone(), Oidc(Arc::new(provider)), form)
            .await
            .expect("oidc redirect should succeed")
            .into_response();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();
        let location = parts.headers.get(LOCATION).unwrap().to_str().unwrap();
        let (base_url, query) = location
            .split_once('?')
            .expect("redirect url to contain query string");

        // Check response matches expectations
        let csrf_state: Option<String> = session.get(OAUTH2_CSRF_STATE_KEY).await.unwrap();
        let nonce: Option<String> = session.get(OIDC_NONCE_KEY).await.unwrap();
        let next_url: Option<Option<String>> = session.get(NEXT_URL_KEY).await.unwrap();
        assert_eq!(parts.status, StatusCode::SEE_OTHER);
        assert_eq!(base_url, "https://issuer.example/authorize");
        assert_eq!(
            csrf_state.as_deref(),
            query
                .split('&')
                .find_map(|pair| pair.strip_prefix("state=").map(String::from))
                .as_deref(),
        );
        assert_eq!(
            nonce.as_deref(),
            query
                .split('&')
                .find_map(|pair| pair.strip_prefix("nonce=").map(String::from))
                .as_deref(),
        );
        assert_eq!(next_url, Some(Some("/dashboard".to_string())));
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_sign_up_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let session_record = empty_session_record(session_id);
        let email_verification_code = Uuid::new_v4();
        let user = sample_auth_user(Uuid::new_v4(), "hash");
        let user_copy = user.clone();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_sign_up_user()
            .times(1)
            .withf(move |cid, summary, verify| {
                *cid == community_id
                    && !matches!(summary.password.as_deref(), Some("secret-password"))
                    && !verify
            })
            .returning(move |_, _, _| Ok((user_copy.clone(), Some(email_verification_code))));
        db.expect_update_session()
            .times(1)
            .withf(move |record| {
                message_matches(
                    record,
                    "Please verify your email to complete the sign up process.",
                )
            })
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue()
            .times(1)
            .withf(move |notification| {
                matches!(&notification.kind, NotificationKind::EmailVerification)
                    && notification.recipients == vec![user.user_id]
                    && notification.template_data
                        == Some(json!({
                            "link": format!("https://app.example/verify-email/{email_verification_code}"),
                        }))
            })
            .returning(|_| Box::pin(async { Ok(()) }));

        // Setup router
        let cfg = HttpServerConfig {
            base_url: "https://app.example".to_string(),
            login: LoginOptions {
                email: true,
                ..Default::default()
            },
            ..Default::default()
        };
        let router = setup_test_router_with_config(cfg, db, nm).await;

        // Setup request
        let form = "email=test%40example.test&name=Test+User&username=test-user&password=secret-password";
        let request = Request::builder()
            .method("POST")
            .uri("/sign-up?next_url=%2Fwelcome")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
            .body(Body::from(form))
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::SEE_OTHER);
        assert_eq!(
            parts.headers.get(LOCATION).unwrap(),
            &HeaderValue::from_static("/log-in?next_url=%2Fwelcome"),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_sign_up_missing_password() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let session_record = empty_session_record(session_id);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_sign_up_user().times(0);

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue().times(0);

        // Setup router
        let mut cfg = HttpServerConfig::default();
        cfg.login.email = true;
        let router = setup_test_router_with_config(cfg, db, nm).await;

        // Setup request (password not provided)
        let form = "email=test%40example.test&name=Test+User&username=test-user";
        let request = Request::builder()
            .method("POST")
            .uri("/sign-up")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
            .body(Body::from(form))
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::BAD_REQUEST);
        assert_eq!(bytes, "password not provided");
    }

    #[tokio::test]
    async fn test_sign_up_db_error() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let session_record = empty_session_record(session_id);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_sign_up_user()
            .times(1)
            .returning(|_, _, _| Err(anyhow!("db error")));
        db.expect_update_session()
            .times(1)
            .withf(move |record| {
                message_matches(
                    record,
                    "Something went wrong while signing up. Please try again later.",
                )
            })
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue().times(0);

        // Setup router
        let mut cfg = HttpServerConfig::default();
        cfg.login.email = true;
        let router = setup_test_router_with_config(cfg, db, nm).await;

        // Setup request
        let form = "email=test%40example.test&name=Test+User&username=test-user&password=secret";
        let request = Request::builder()
            .method("POST")
            .uri("/sign-up")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
            .body(Body::from(form))
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::SEE_OTHER);
        assert_eq!(
            parts.headers.get(LOCATION).unwrap(),
            &HeaderValue::from_static(SIGN_UP_URL),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_update_user_details_success() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_update_user_details()
            .times(1)
            .withf(move |uid, details| *uid == user_id && details.name == "Updated User")
            .returning(|_, _| Ok(()));
        db.expect_update_session()
            .times(1)
            .withf(move |record| message_matches(record, "User details updated successfully."))
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("PUT")
            .uri("/dashboard/account/update/details")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
            .body(Body::from("name=Updated+User&company=Example"))
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::NO_CONTENT);
        assert_eq!(
            parts.headers.get("HX-Trigger").unwrap(),
            &HeaderValue::from_static("refresh-body"),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_update_user_details_invalid_body() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_update_user_details().times(0);

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let request = Request::builder()
            .method("PUT")
            .uri("/dashboard/account/update/details")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::from("invalid"))
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
        assert!(!bytes.is_empty());
    }

    #[tokio::test]
    async fn test_update_user_password_success() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None);
        let existing_password_hash = password_auth::generate_hash("current-password");

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_get_user_password()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(existing_password_hash.clone())));
        db.expect_update_user_password()
            .times(1)
            .withf(move |uid, new_password| *uid == user_id && new_password != "new-password")
            .returning(|_, _| Ok(()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let form = "old_password=current-password&new_password=new-password";
        let request = Request::builder()
            .method("PUT")
            .uri("/dashboard/account/update/password")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
            .body(Body::from(form))
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::SEE_OTHER);
        assert!(bytes.is_empty());
        assert_eq!(
            parts.headers.get(LOCATION).unwrap(),
            &HeaderValue::from_static(LOG_OUT_URL),
        );
    }

    #[tokio::test]
    async fn test_update_user_password_wrong_old_password() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None);
        let existing_password_hash = password_auth::generate_hash("current-password");

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_get_user_password()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(existing_password_hash.clone())));
        db.expect_update_user_password().times(0);

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = setup_test_router(db, nm).await;
        let form = "old_password=wrong-password&new_password=new-password";
        let request = Request::builder()
            .method("PUT")
            .uri("/dashboard/account/update/password")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
            .body(Body::from(form))
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::FORBIDDEN);
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_verify_email_success() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let session_record = empty_session_record(session_id);
        let verification_code = Uuid::new_v4();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_verify_email()
            .times(1)
            .withf(move |code| *code == verification_code)
            .returning(|_| Ok(()));
        db.expect_update_session()
            .times(1)
            .withf(move |record| {
                message_matches(
                    record,
                    "Email verified successfully. You can now log in using your credentials.",
                )
            })
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let mut cfg = HttpServerConfig::default();
        cfg.login.email = true;
        let router = setup_test_router_with_config(cfg, db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri(format!("/verify-email/{verification_code}"))
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::SEE_OTHER);
        assert!(bytes.is_empty());
        assert_eq!(
            parts.headers.get(LOCATION).unwrap(),
            &HeaderValue::from_static(LOG_IN_URL),
        );
    }

    #[tokio::test]
    async fn test_verify_email_failure() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let session_record = empty_session_record(session_id);
        let verification_code = Uuid::new_v4();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_verify_email()
            .times(1)
            .withf(move |code| *code == verification_code)
            .returning(|_| Err(anyhow!("db error")));
        db.expect_update_session()
            .times(1)
            .withf(move |record| {
                message_matches(
                    record,
                    "Error verifying email (please note that links are only valid for 24 hours).",
                )
            })
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let mut cfg = HttpServerConfig::default();
        cfg.login.email = true;
        let router = setup_test_router_with_config(cfg, db, nm).await;
        let request = Request::builder()
            .method("GET")
            .uri(format!("/verify-email/{verification_code}"))
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::SEE_OTHER);
        assert!(bytes.is_empty());
        assert_eq!(
            parts.headers.get(LOCATION).unwrap(),
            &HeaderValue::from_static(LOG_IN_URL),
        );
    }

    #[test]
    fn test_get_log_in_url_without_next() {
        let url = get_log_in_url(None);
        assert_eq!(url, LOG_IN_URL);
    }

    #[test]
    fn test_get_log_in_url_with_next() {
        let url = get_log_in_url(Some("/dashboard"));
        assert_eq!(url, "/log-in?next_url=%2Fdashboard");
    }

    #[test]
    fn test_sanitize_next_url_accepts_internal_paths() {
        assert_eq!(
            sanitize_next_url(Some("/dashboard")),
            Some("/dashboard".to_string())
        );
        assert_eq!(
            sanitize_next_url(Some("/groups?page=2#section")),
            Some("/groups?page=2#section".to_string())
        );
        assert_eq!(
            sanitize_next_url(Some("   /profile  ")),
            Some("/profile".to_string())
        );
    }

    #[test]
    fn test_sanitize_next_url_rejects_external_paths() {
        assert_eq!(sanitize_next_url(Some("")), None);
        assert_eq!(sanitize_next_url(Some("https://evil.example")), None);
        assert_eq!(sanitize_next_url(Some("//evil.example")), None);
        assert_eq!(sanitize_next_url(Some("javascript:alert(1)")), None);
        assert_eq!(sanitize_next_url(Some("relative/path")), None);
    }

    #[tokio::test]
    async fn test_user_belongs_to_any_group_team_allows_request() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));

        // Setup router
        let cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            cfg: cfg.clone(),
            db: db.clone(),
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs::Config::new(3, false),
        };
        let auth_layer = crate::auth::setup_layer(&cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route("/protected", get(|| async { StatusCode::OK }))
            .layer(middleware::from_fn(user_belongs_to_any_group_team))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri("/protected")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::OK);
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_user_belongs_to_any_group_team_forbidden_for_non_member() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| {
                let mut user = sample_auth_user(user_id, &auth_hash);
                user.belongs_to_any_group_team = Some(false);
                Ok(Some(user))
            });

        // Setup router
        let cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            cfg: cfg.clone(),
            db: db.clone(),
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs::Config::new(3, false),
        };
        let auth_layer = crate::auth::setup_layer(&cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route("/protected", get(|| async { StatusCode::OK }))
            .layer(middleware::from_fn(user_belongs_to_any_group_team))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri("/protected")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::FORBIDDEN);
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_user_belongs_to_any_group_team_forbidden_when_not_logged_in() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let session_record = empty_session_record(session_id);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id().times(0);

        // Setup router
        let cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            cfg: cfg.clone(),
            db: db.clone(),
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs::Config::new(3, false),
        };
        let auth_layer = crate::auth::setup_layer(&cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route("/protected", get(|| async { StatusCode::OK }))
            .layer(middleware::from_fn(user_belongs_to_any_group_team))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri("/protected")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::FORBIDDEN);
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_user_owns_community_allows_request() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let community_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_user_owns_community()
            .times(1)
            .withf(move |cid, uid| *cid == community_id && *uid == user_id)
            .returning(|_, _| Ok(true));

        // Setup router
        let cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            cfg: cfg.clone(),
            db: db.clone(),
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs::Config::new(3, false),
        };
        let auth_layer = crate::auth::setup_layer(&cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route("/protected", get(|| async { StatusCode::OK }))
            .layer(middleware::from_fn_with_state(state.clone(), user_owns_community))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri("/protected")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::OK);
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_user_owns_community_forbidden_when_not_owner() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let community_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_user_owns_community()
            .times(1)
            .withf(move |cid, uid| *cid == community_id && *uid == user_id)
            .returning(|_, _| Ok(false));

        // Setup router
        let cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            cfg: cfg.clone(),
            db: db.clone(),
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs::Config::new(3, false),
        };
        let auth_layer = crate::auth::setup_layer(&cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route("/protected", get(|| async { StatusCode::OK }))
            .layer(middleware::from_fn_with_state(state.clone(), user_owns_community))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri("/protected")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::FORBIDDEN);
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_user_owns_community_returns_error_on_db_failure() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let community_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_user_owns_community()
            .times(1)
            .withf(move |cid, uid| *cid == community_id && *uid == user_id)
            .returning(|_, _| Err(anyhow!("db error")));

        // Setup router
        let cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            cfg: cfg.clone(),
            db: db.clone(),
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs::Config::new(3, false),
        };
        let auth_layer = crate::auth::setup_layer(&cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route("/protected", get(|| async { StatusCode::OK }))
            .layer(middleware::from_fn_with_state(state.clone(), user_owns_community))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri("/protected")
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_user_owns_group_allows_request() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_user_owns_group()
            .times(1)
            .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(true));

        // Setup router
        let cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            cfg: cfg.clone(),
            db: db.clone(),
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs::Config::new(3, false),
        };
        let auth_layer = crate::auth::setup_layer(&cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route("/groups/{group_id}", get(|| async { StatusCode::OK }))
            .layer(middleware::from_fn_with_state(state.clone(), user_owns_group))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri(format!("/groups/{group_id}"))
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::OK);
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_user_owns_group_forbidden_when_not_owner() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_user_owns_group()
            .times(1)
            .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(false));

        // Setup router
        let cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            cfg: cfg.clone(),
            db: db.clone(),
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs::Config::new(3, false),
        };
        let auth_layer = crate::auth::setup_layer(&cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route("/groups/{group_id}", get(|| async { StatusCode::OK }))
            .layer(middleware::from_fn_with_state(state.clone(), user_owns_group))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri(format!("/groups/{group_id}"))
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::FORBIDDEN);
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_user_owns_group_returns_error_on_db_failure() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
        db.expect_get_community_id()
            .times(1)
            .withf(|host| host == "example.test")
            .returning(move |_| Ok(Some(community_id)));
        db.expect_user_owns_group()
            .times(1)
            .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Err(anyhow!("db error")));

        // Setup router
        let cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            cfg: cfg.clone(),
            db: db.clone(),
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs::Config::new(3, false),
        };
        let auth_layer = crate::auth::setup_layer(&cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route("/groups/{group_id}", get(|| async { StatusCode::OK }))
            .layer(middleware::from_fn_with_state(state.clone(), user_owns_group))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri(format!("/groups/{group_id}"))
            .header(HOST, "example.test")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
        assert!(bytes.is_empty());
    }

    fn empty_session_record(session_id: session::Id) -> session::Record {
        session::Record {
            data: HashMap::default(),
            expiry_date: OffsetDateTime::now_utc(),
            id: session_id,
        }
    }

    fn record_contains_selected_group(record: &session::Record, group_id: Uuid) -> bool {
        record
            .data
            .get(SELECTED_GROUP_ID_KEY)
            .and_then(|value| value.as_str())
            .and_then(|value| value.parse::<Uuid>().ok())
            == Some(group_id)
    }
}
