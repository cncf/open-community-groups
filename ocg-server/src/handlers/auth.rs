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
use serde::Deserialize;
use tower_sessions::Session;
use tracing::{info, instrument};
use uuid::Uuid;

use crate::{
    auth::{self, AuthSession, Credentials, OAuth2Credentials, OidcCredentials, PasswordCredentials},
    config::{HttpServerConfig, OAuth2Provider, OidcProvider},
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CommunityId, OAuth2, Oidc},
    },
    templates::{self, PageId, auth::User},
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

// Pages handlers.

/// Handler that returns the log in page.
#[instrument(skip_all, err)]
pub(crate) async fn log_in_page(
    auth_session: AuthSession,
    messages: Messages,
    State(cfg): State<HttpServerConfig>,
    Query(query): Query<HashMap<String, String>>,
) -> Result<impl IntoResponse, HandlerError> {
    // Check if the user is already logged in
    if auth_session.user.is_some() {
        return Ok(Redirect::to("/").into_response());
    }

    // Prepare template
    let template = templates::auth::LogInPage {
        login: cfg.login.clone(),
        messages: messages.into_iter().collect(),
        page_id: PageId::LogIn,
        user: User::default(),

        auth_provider: None,
        next_url: query.get("next_url").cloned(),
    };

    Ok(Html(template.render()?).into_response())
}

/// Handler that returns the sign up page.
#[instrument(skip_all, err)]
pub(crate) async fn sign_up_page(
    auth_session: AuthSession,
    messages: Messages,
    State(cfg): State<HttpServerConfig>,
    Query(query): Query<HashMap<String, String>>,
) -> Result<impl IntoResponse, HandlerError> {
    // Check if the user is already logged in
    if auth_session.user.is_some() {
        return Ok(Redirect::to("/").into_response());
    }

    // Prepare template
    let template = templates::auth::SignUpPage {
        login: cfg.login.clone(),
        messages: messages.into_iter().collect(),
        page_id: PageId::SignUp,
        user: User::default(),

        auth_provider: None,
        next_url: query.get("next_url").cloned(),
    };

    Ok(Html(template.render()?).into_response())
}

// Actions handlers.

/// Handler that logs the user in.
#[instrument(skip_all)]
pub(crate) async fn log_in(
    mut auth_session: AuthSession,
    messages: Messages,
    session: Session,
    State(db): State<DynDB>,
    Query(query): Query<HashMap<String, String>>,
    Form(creds): Form<PasswordCredentials>,
) -> Result<impl IntoResponse, HandlerError> {
    // Authenticate user
    let Some(user) = auth_session
        .authenticate(Credentials::Password(creds.clone()))
        .await
        .map_err(|e| HandlerError::Auth(e.to_string()))?
    else {
        messages.error("Invalid credentials. Please make sure you have verified your email address.");
        let log_in_url = get_log_in_url(query.get("next_url"));
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

    // Prepare next url
    let next_url = if let Some(next_url) = query.get("next_url") {
        next_url
    } else {
        "/"
    };

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
    let next_url = session.remove::<Option<String>>(NEXT_URL_KEY).await?.flatten();
    let log_in_url = get_log_in_url(next_url.as_ref());

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

    // Prepare next url
    let next_url = next_url.unwrap_or("/".to_string());

    Ok(Redirect::to(&next_url))
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
    let next_url = session.remove::<Option<String>>(NEXT_URL_KEY).await?.flatten();
    let log_in_url = get_log_in_url(next_url.as_ref());

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

    // Prepare next url
    let next_url = next_url.unwrap_or("/".to_string());

    Ok(Redirect::to(&next_url))
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
    let Ok((_user, email_verification_code)) = db.sign_up_user(&community_id, &user_summary, false).await
    else {
        // Redirect to the sign up page on error
        messages.error("Something went wrong while signing up. Please try again later.");
        return Ok(Redirect::to(SIGN_UP_URL).into_response());
    };

    // Enqueue email verification notification
    if let Some(code) = email_verification_code {
        // TODO: send email verification notification

        // Temporarily print the verification URL to the console
        let verification_url = format!("{}/verify-email/{}", cfg.base_url, code);
        info!(%verification_url, "Email verification URL (temporary)");

        messages.success("Please verify your email to complete the sign up process.");
    }

    // Redirect to the log in page on success
    let log_in_url = get_log_in_url(query.get("next_url"));
    Ok(Redirect::to(&log_in_url).into_response())
}

/// Handler that updates the user's details.
#[instrument(skip_all, err)]
pub(crate) async fn update_user_details(
    auth_session: AuthSession,
    messages: Messages,
    State(db): State<DynDB>,
    Form(user_data): Form<auth::User>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session
    let Some(user) = auth_session.user else {
        return Ok(StatusCode::FORBIDDEN.into_response());
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
    Form(mut input): Form<auth::PasswordUpdateInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session
    let Some(user) = auth_session.user else {
        return Ok(StatusCode::FORBIDDEN.into_response());
    };

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
    Ok(Redirect::to(LOG_IN_URL).into_response())
}

/// Get the log in url including the next url if provided.
fn get_log_in_url(next_url: Option<&String>) -> String {
    let mut log_in_url = LOG_IN_URL.to_string();
    if let Some(next_url) = next_url {
        log_in_url = format!("{log_in_url}?next_url={next_url}");
    }
    log_in_url
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
    let Ok(user_owns_community) = db.user_owns_community(&user.user_id, &community_id).await else {
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
    let Ok(user_owns_group) = db.user_owns_group(&user.user_id, &group_id).await else {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    };
    if !user_owns_group {
        return StatusCode::FORBIDDEN.into_response();
    }

    next.run(request).await.into_response()
}
