//! This module defines the handlers used for authentication: log in and sign
//! up pages, password and external provider log in, and account maintenance.
//! The dashboard authorization middleware lives in `middleware` and the
//! session dashboard context helpers in `session_context`.

use std::collections::HashMap;

use askama::Template;
use async_trait::async_trait;
use axum::{
    Form,
    extract::{Path, Query, State},
    http::StatusCode,
    response::{Html, IntoResponse, Redirect},
};
use axum_messages::Messages;
use garde::Validate;
use openidconnect as oidc;
use password_auth::verify_password;
use percent_encoding::{NON_ALPHANUMERIC, utf8_percent_encode};
use serde::Deserialize;
use tower_sessions::Session;
use tracing::{instrument, warn};
use uuid::Uuid;

use crate::{
    auth::{
        self, AUTH_PROVIDER_KEY, AuthSession, Credentials, OAuth2Credentials, OidcCredentials,
        PasswordCredentials,
    },
    config::{HttpServerConfig, OAuth2Provider, OidcProvider},
    db::{DynDB, auth::EmailVerificationNotification},
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, OAuth2, Oidc, ValidatedForm, ValidatedFormQs},
    },
    templates::{self, PageId, auth::UserMenuState, notifications::EmailVerification},
    types::user::{UserDetailsInput, UserPasswordInput},
    util::base_url_without_trailing_slash,
    validation::{MAX_LEN_S, trimmed_non_empty},
};

use self::session_context::select_first_community_and_group;

pub(crate) mod middleware;
pub(crate) mod session_context;
#[cfg(test)]
mod tests;

/// Session value for password authentication.
pub(crate) const AUTH_PROVIDER_EMAIL: &str = "email";

/// Friendly message for LF SSO email ownership conflicts.
const LF_SSO_EMAIL_CONFLICT_MESSAGE: &str = concat!(
    "Your LF SSO account matches an existing OCG account, but its email address is already used ",
    "by another account. Please contact the site administrators."
);

/// Friendly message for LF SSO identity ownership conflicts.
const LF_SSO_IDENTITY_CONFLICT_MESSAGE: &str =
    "This LF SSO account is already linked to another OCG account.";

/// URL for the log in page.
pub(crate) const LOG_IN_URL: &str = "/log-in";

/// Key used to store the next URL in the session.
pub(crate) const NEXT_URL_KEY: &str = "next_url";

/// Key used to store the `OAuth2` CSRF state in the session.
pub(crate) const OAUTH2_CSRF_STATE_KEY: &str = "oauth2.csrf_state";

/// Key used to store the `Oidc` nonce in the session.
pub(crate) const OIDC_NONCE_KEY: &str = "oidc.nonce";

/// URL for the sign up page.
pub(crate) const SIGN_UP_URL: &str = "/sign-up";

// Pages and sections handlers.

/// Handler that returns the log in page.
#[instrument(skip_all, err)]
pub(crate) async fn log_in_page(
    auth_session: AuthSession,
    messages: Messages,
    State(db): State<DynDB>,
    State(server_cfg): State<HttpServerConfig>,
    Query(query): Query<HashMap<String, String>>,
) -> Result<impl IntoResponse, HandlerError> {
    // Check if the user is already logged in
    if auth_session.user.is_some() {
        return Ok(Redirect::to("/").into_response());
    }

    // Get site settings
    let site_settings = db.get_site_settings().await?;

    // Sanitize and encode the next url (if any)
    let next_url = sanitize_next_url(query.get("next_url").map(String::as_str))
        .map(|value| encode_next_url(&value));

    // Prepare template
    let template = templates::auth::LogInPage {
        login: server_cfg.login.clone(),
        messages: messages.into_iter().collect(),
        page_id: PageId::LogIn,
        path: LOG_IN_URL.to_string(),
        site_settings,
        user: UserMenuState::default(),

        next_url,
    };

    Ok(Html(template.render()?).into_response())
}

/// Handler that returns the sign up page.
#[instrument(skip_all, err)]
pub(crate) async fn sign_up_page(
    auth_session: AuthSession,
    messages: Messages,
    State(db): State<DynDB>,
    State(server_cfg): State<HttpServerConfig>,
    Query(query): Query<HashMap<String, String>>,
) -> Result<impl IntoResponse, HandlerError> {
    // Check if the user is already logged in
    if auth_session.user.is_some() {
        return Ok(Redirect::to("/").into_response());
    }

    // Get site settings
    let site_settings = db.get_site_settings().await?;

    // Sanitize and encode the next url (if any)
    let next_url = sanitize_next_url(query.get("next_url").map(String::as_str))
        .map(|value| encode_next_url(&value));

    // Prepare template
    let template = templates::auth::SignUpPage {
        login: server_cfg.login.clone(),
        messages: messages.into_iter().collect(),
        page_id: PageId::SignUp,
        path: SIGN_UP_URL.to_string(),
        site_settings,
        user: UserMenuState::default(),

        next_url,
    };

    Ok(Html(template.render()?).into_response())
}

/// Handler for rendering the user menu section.
#[instrument(skip_all, err)]
pub(crate) async fn user_menu_section(
    auth_session: AuthSession,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let template = templates::auth::UserMenuSection {
        user: UserMenuState::from_session(auth_session).await?,
    };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Handler that logs the user in.
#[instrument(skip_all, err)]
pub(crate) async fn log_in(
    mut auth_session: AuthSession,
    messages: Messages,
    session: Session,
    State(db): State<DynDB>,
    Query(query): Query<HashMap<String, String>>,
    Form(login_form): Form<LoginForm>,
) -> Result<impl IntoResponse, HandlerError> {
    // Sanitize next url
    let next_url = sanitize_next_url(query.get("next_url").map(String::as_str));

    // Validate form
    if let Err(e) = login_form.validate() {
        messages.error(e.to_string());
        let log_in_url = get_log_in_url(next_url.as_deref());
        return Ok(Redirect::to(&log_in_url));
    }

    // Authenticate user
    let creds = PasswordCredentials {
        password: login_form.password,
        username: login_form.username,
    };
    let Some(user) = auth_session
        .authenticate(Credentials::Password(creds))
        .await
        .map_err(|_| HandlerError::Auth)?
    else {
        messages
            .error("Invalid credentials. Please make sure you have verified your email address.");
        let log_in_url = get_log_in_url(next_url.as_deref());
        return Ok(Redirect::to(&log_in_url));
    };

    // Log user in
    auth_session.login(&user).await.map_err(|_| HandlerError::Auth)?;

    // Select the first community and group as selected in the session
    select_first_community_and_group(&db, &session, &user.user_id).await?;

    // Track auth provider in the session
    track_auth_provider(&session, AUTH_PROVIDER_EMAIL).await?;

    let next_url = next_url.as_deref().unwrap_or("/");
    Ok(Redirect::to(next_url))
}

/// Handler that logs the user out.
#[instrument(skip_all, err)]
pub(crate) async fn log_out(
    mut auth_session: AuthSession,
) -> Result<impl IntoResponse, HandlerError> {
    auth_session.logout().await.map_err(|_| HandlerError::Auth)?;

    Ok(Redirect::to(LOG_IN_URL))
}

/// Handler that completes the oauth2 authorization process.
#[instrument(skip_all, err)]
pub(crate) async fn oauth2_callback(
    mut auth_session: AuthSession,
    messages: Messages,
    session: Session,
    State(db): State<DynDB>,
    Path(provider): Path<OAuth2Provider>,
    Query(OAuth2AuthorizationResponse { code, state }): Query<OAuth2AuthorizationResponse>,
) -> Result<impl IntoResponse, HandlerError> {
    oauth2_callback_with_auth(
        &mut auth_session,
        session,
        &db,
        provider,
        code,
        state,
        |message| drop(messages.error(message)),
    )
    .await
}

/// Handler that redirects the user to the oauth2 provider.
#[instrument(skip_all, err)]
pub(crate) async fn oauth2_redirect(
    session: Session,
    OAuth2(oauth2_provider): OAuth2,
    Query(NextUrl { next_url }): Query<NextUrl>,
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
#[instrument(skip_all, err)]
pub(crate) async fn oidc_callback(
    mut auth_session: AuthSession,
    messages: Messages,
    session: Session,
    State(db): State<DynDB>,
    Path(provider): Path<OidcProvider>,
    Query(OAuth2AuthorizationResponse { code, state }): Query<OAuth2AuthorizationResponse>,
) -> Result<impl IntoResponse, HandlerError> {
    oidc_callback_with_auth(
        &mut auth_session,
        session,
        &db,
        provider,
        code,
        state,
        |message| drop(messages.error(message)),
    )
    .await
}

/// Handler that redirects the user to the oidc provider.
#[instrument(skip_all, err)]
pub(crate) async fn oidc_redirect(
    session: Session,
    Oidc(oidc_provider): Oidc,
    Query(NextUrl { next_url }): Query<NextUrl>,
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
#[instrument(skip_all, err)]
pub(crate) async fn sign_up(
    messages: Messages,
    State(db): State<DynDB>,
    State(server_cfg): State<HttpServerConfig>,
    Query(query): Query<HashMap<String, String>>,
    Form(mut profile): Form<auth::ExternalUserProfile>,
) -> Result<impl IntoResponse, HandlerError> {
    // Sanitize next url
    let next_url = sanitize_next_url(query.get("next_url").map(String::as_str));

    // Validate form
    if let Err(e) = profile.validate() {
        messages.error(e.to_string());
        return Ok(get_sign_up_url(next_url.as_deref()).into_response());
    }

    // Check if the password has been provided
    let Some(password) = profile.password.take() else {
        return Ok((StatusCode::BAD_REQUEST, "password not provided").into_response());
    };

    // Generate password hash off the async executor
    let password_hash =
        tokio::task::spawn_blocking(move || password_auth::generate_hash(&password))
            .await
            .map_err(anyhow::Error::from)?;
    profile.password = Some(password_hash);

    // Prepare the required email verification notification before mutating users
    let Ok(verification) = build_email_verification_notification(&db, &server_cfg).await else {
        messages.error("Something went wrong while signing up. Please try again later.");
        return Ok(Redirect::to(SIGN_UP_URL).into_response());
    };

    // Sign up the user, reusing pre-registered invitation placeholders when present
    let sign_up_result = match db
        .activate_pre_registered_user_email_password(&profile, &verification)
        .await
    {
        Ok(Some((user, verification_code))) => Ok((user, Some(verification_code))),
        Ok(None) => db.sign_up_user(&profile, false, Some(verification)).await,
        Err(err) => Err(err),
    };
    let Ok((_user, email_verification_code)) = sign_up_result else {
        // Redirect to the sign up page on error
        messages.error("Something went wrong while signing up. Please try again later.");
        return Ok(Redirect::to(SIGN_UP_URL).into_response());
    };

    // Notify the user that database-side verification email enqueue was requested
    if email_verification_code.is_some() {
        messages.success("Please verify your email to complete the sign up process.");
    }

    // Redirect to the log in page on success
    let log_in_url = get_log_in_url(next_url.as_deref());
    Ok(Redirect::to(&log_in_url).into_response())
}

/// Handler that updates the user's details.
#[instrument(skip_all, err)]
pub(crate) async fn update_user_details(
    CurrentUser(user): CurrentUser,
    messages: Messages,
    State(db): State<DynDB>,
    ValidatedFormQs(user_data): ValidatedFormQs<UserDetailsInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Update user in database
    let user_id = user.user_id;
    db.update_user_details(&user_id, &user_data).await?;
    messages.success("User details updated successfully.");

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]).into_response())
}

/// Handler that updates the user's password.
#[instrument(skip_all, err)]
pub(crate) async fn update_user_password(
    mut auth_session: AuthSession,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    ValidatedForm(input): ValidatedForm<UserPasswordInput>,
) -> Result<impl IntoResponse, HandlerError> {
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

    // Hash the new password off the async executor and update it in database
    let new_password_hash =
        tokio::task::spawn_blocking(move || password_auth::generate_hash(&input.new_password))
            .await
            .map_err(anyhow::Error::from)?;
    db.update_user_password(&user.user_id, &new_password_hash).await?;

    // Best-effort invalidate the current session after changing credentials
    if let Err(err) = auth_session.logout().await {
        warn!(error = %err, "failed to delete current session after password change");
    }

    Ok(Redirect::to(LOG_IN_URL).into_response())
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
        messages
            .error("Error verifying email (please note that links are only valid for 24 hours).");
    }
    Ok(Redirect::to(LOG_IN_URL))
}

// Auth callback helpers.

#[async_trait]
trait CallbackAuth {
    async fn authenticate_oauth2(
        &mut self,
        code: String,
        provider: OAuth2Provider,
    ) -> Result<Option<auth::User>, String>;

    async fn authenticate_oidc(
        &mut self,
        code: String,
        nonce: oidc::Nonce,
        provider: OidcProvider,
    ) -> Result<Option<auth::User>, String>;

    async fn log_in(&mut self, user: &auth::User) -> Result<(), HandlerError>;
}

#[async_trait]
impl CallbackAuth for AuthSession {
    async fn authenticate_oauth2(
        &mut self,
        code: String,
        provider: OAuth2Provider,
    ) -> Result<Option<auth::User>, String> {
        self.authenticate(Credentials::OAuth2(OAuth2Credentials { code, provider }))
            .await
            .map_err(|e| e.to_string())
    }

    async fn authenticate_oidc(
        &mut self,
        code: String,
        nonce: oidc::Nonce,
        provider: OidcProvider,
    ) -> Result<Option<auth::User>, String> {
        self.authenticate(Credentials::Oidc(OidcCredentials {
            code,
            nonce,
            provider,
        }))
        .await
        .map_err(|e| e.to_string())
    }

    async fn log_in(&mut self, user: &auth::User) -> Result<(), HandlerError> {
        self.login(user).await.map_err(|_| HandlerError::Auth)
    }
}

async fn oauth2_callback_with_auth<A, F>(
    auth: &mut A,
    session: Session,
    db: &DynDB,
    provider: OAuth2Provider,
    code: String,
    state: oauth2::CsrfToken,
    on_error: F,
) -> Result<Redirect, HandlerError>
where
    A: CallbackAuth,
    F: FnOnce(String),
{
    const OAUTH2_AUTHORIZATION_FAILED: &str = "OAuth2 authorization failed";

    // Verify oauth2 csrf state
    let Some(state_in_session) = session.remove::<oauth2::CsrfToken>(OAUTH2_CSRF_STATE_KEY).await?
    else {
        on_error(OAUTH2_AUTHORIZATION_FAILED.to_string());
        return Ok(Redirect::to(LOG_IN_URL));
    };
    if state_in_session.secret() != state.secret() {
        on_error(OAUTH2_AUTHORIZATION_FAILED.to_string());
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
    let user = match auth.authenticate_oauth2(code, provider.clone()).await {
        Ok(Some(user)) => user,
        Ok(None) => {
            on_error(OAUTH2_AUTHORIZATION_FAILED.to_string());
            return Ok(Redirect::to(&log_in_url));
        }
        Err(err) => {
            on_error(format!("{OAUTH2_AUTHORIZATION_FAILED}: {err}"));
            return Ok(Redirect::to(&log_in_url));
        }
    };

    // Log user in
    auth.log_in(&user).await?;

    // Select the first community and group as selected in the session
    select_first_community_and_group(db, &session, &user.user_id).await?;

    // Track auth provider in the session
    track_auth_provider(&session, provider.as_ref()).await?;

    let next_url = next_url.as_deref().unwrap_or("/");
    Ok(Redirect::to(next_url))
}

async fn oidc_callback_with_auth<A, F>(
    auth: &mut A,
    session: Session,
    db: &DynDB,
    provider: OidcProvider,
    code: String,
    state: oauth2::CsrfToken,
    on_error: F,
) -> Result<Redirect, HandlerError>
where
    A: CallbackAuth,
    F: FnOnce(String),
{
    const OIDC_AUTHORIZATION_FAILED: &str = "OpenID Connect authorization failed";

    // Verify oauth2 csrf state
    let Some(state_in_session) = session.remove::<oauth2::CsrfToken>(OAUTH2_CSRF_STATE_KEY).await?
    else {
        on_error(OIDC_AUTHORIZATION_FAILED.to_string());
        return Ok(Redirect::to(LOG_IN_URL));
    };
    if state_in_session.secret() != state.secret() {
        on_error(OIDC_AUTHORIZATION_FAILED.to_string());
        return Ok(Redirect::to(LOG_IN_URL));
    }

    // Get oidc nonce from session
    let Some(nonce) = session.remove::<oidc::Nonce>(OIDC_NONCE_KEY).await? else {
        on_error(OIDC_AUTHORIZATION_FAILED.to_string());
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
    let user = match auth.authenticate_oidc(code, nonce, provider.clone()).await {
        Ok(Some(user)) => user,
        Ok(None) => {
            on_error(OIDC_AUTHORIZATION_FAILED.to_string());
            return Ok(Redirect::to(&log_in_url));
        }
        Err(err) => {
            on_error(oidc_authorization_error_message(&err));
            return Ok(Redirect::to(&log_in_url));
        }
    };

    // Log user in
    auth.log_in(&user).await?;

    // Select the first community and group as selected in the session
    select_first_community_and_group(db, &session, &user.user_id).await?;

    // Track auth provider in the session
    track_auth_provider(&session, provider.as_ref()).await?;

    let next_url = next_url.as_deref().unwrap_or("/");
    Ok(Redirect::to(next_url))
}

// Types.

/// Login form data from the user.
#[derive(Debug, Deserialize, Validate)]
pub(crate) struct LoginForm {
    /// Password for authentication.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_S))]
    pub password: String,
    /// Username for authentication.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_S))]
    pub username: String,
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

// Helpers.

/// Builds the email verification notification payload required by password signup.
async fn build_email_verification_notification(
    db: &DynDB,
    server_cfg: &HttpServerConfig,
) -> Result<EmailVerificationNotification, HandlerError> {
    // Prepare verification link inputs before loading template context
    let code = Uuid::new_v4();
    let base_url = base_url_without_trailing_slash(&server_cfg.base_url);
    if base_url.is_empty() {
        return Err(HandlerError::Rejected(
            "base URL is required to send verification email".to_string(),
        ));
    }

    // Build template data from the current site theme
    let site_settings = db.get_site_settings().await?;
    let template_data = serde_json::to_value(EmailVerification {
        link: format!("{base_url}/verify-email/{code}"),
        theme: site_settings.theme,
    })?;

    // Return the database-ready verification notification payload
    Ok(EmailVerificationNotification {
        code,
        template_data,
    })
}

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

/// Get the sign up url including the next url if provided.
fn get_sign_up_url(next_url: Option<&str>) -> Redirect {
    let mut sign_up_url = SIGN_UP_URL.to_string();
    if let Some(next_url) = sanitize_next_url(next_url) {
        sign_up_url = format!("{sign_up_url}?next_url={}", encode_next_url(&next_url));
    }
    Redirect::to(&sign_up_url)
}

/// Formats OIDC authorization errors for user-facing flash messages.
fn oidc_authorization_error_message(err: &str) -> String {
    if err.contains(auth::EXTERNAL_AUTH_EMAIL_CONFLICT_ERROR) {
        return LF_SSO_EMAIL_CONFLICT_MESSAGE.to_string();
    }

    if err.contains(auth::EXTERNAL_AUTH_IDENTITY_CONFLICT_ERROR) {
        return LF_SSO_IDENTITY_CONFLICT_MESSAGE.to_string();
    }

    format!("OpenID Connect authorization failed: {err}")
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

/// Stores the authentication provider used for the current login.
async fn track_auth_provider(session: &Session, provider: &str) -> Result<(), HandlerError> {
    session.insert(AUTH_PROVIDER_KEY, provider).await?;
    Ok(())
}
