//! This module defines some handlers used for authentication.

use std::collections::HashMap;

use askama::Template;
use async_trait::async_trait;
use axum::{
    Form,
    extract::{Path, Query, Request, State},
    http::StatusCode,
    middleware::Next,
    response::{Html, IntoResponse, Redirect},
};
use axum_messages::Messages;
use garde::Validate;
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
        extractors::{
            CurrentUser, OAuth2, Oidc, SelectedCommunityId, SelectedGroupId, ValidatedForm, ValidatedFormQs,
        },
    },
    services::notifications::{DynNotificationsManager, NewNotification, NotificationKind},
    templates::{
        self, PageId,
        auth::{User, UserDetails},
        notifications::EmailVerification,
    },
    validation::{MAX_LEN_S, trimmed_non_empty},
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

/// Key used to store the selected community ID in the session.
pub(crate) const SELECTED_COMMUNITY_ID_KEY: &str = "selected_community_id";

/// Key used to store the selected group ID in the session.
pub(crate) const SELECTED_GROUP_ID_KEY: &str = "selected_group_id";

/// URL for the sign up page.
pub(crate) const SIGN_UP_URL: &str = "/sign-up";

/// URL for user dashboard invitations tab.
pub(crate) const USER_DASHBOARD_INVITATIONS_URL: &str = "/dashboard/user?tab=invitations";

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
    let next_url =
        sanitize_next_url(query.get("next_url").map(String::as_str)).map(|value| encode_next_url(&value));

    // Prepare template
    let template = templates::auth::LogInPage {
        login: server_cfg.login.clone(),
        messages: messages.into_iter().collect(),
        page_id: PageId::LogIn,
        path: LOG_IN_URL.to_string(),
        site_settings,
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
    let next_url =
        sanitize_next_url(query.get("next_url").map(String::as_str)).map(|value| encode_next_url(&value));

    // Prepare template
    let template = templates::auth::SignUpPage {
        login: server_cfg.login.clone(),
        messages: messages.into_iter().collect(),
        page_id: PageId::SignUp,
        path: SIGN_UP_URL.to_string(),
        site_settings,
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

    // Select the first community and group as selected in the session
    select_first_community_and_group(&db, &session, &user.user_id).await?;

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
#[instrument(skip_all)]
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
#[instrument(skip_all)]
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
#[instrument(skip_all)]
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
#[instrument(skip_all)]
pub(crate) async fn sign_up(
    messages: Messages,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    Query(query): Query<HashMap<String, String>>,
    Form(mut user_summary): Form<auth::UserSummary>,
) -> Result<impl IntoResponse, HandlerError> {
    // Sanitize next url
    let next_url = sanitize_next_url(query.get("next_url").map(String::as_str));

    // Validate form
    if let Err(e) = user_summary.validate() {
        messages.error(e.to_string());
        return Ok(get_sign_up_url(next_url.as_deref()).into_response());
    }

    // Check if the password has been provided
    let Some(password) = user_summary.password.take() else {
        return Ok((StatusCode::BAD_REQUEST, "password not provided").into_response());
    };

    // Generate password hash
    user_summary.password = Some(password_auth::generate_hash(&password));

    // Sign up the user
    let Ok((user, email_verification_code)) = db.sign_up_user(&user_summary, false).await else {
        // Redirect to the sign up page on error
        messages.error("Something went wrong while signing up. Please try again later.");
        return Ok(Redirect::to(SIGN_UP_URL).into_response());
    };

    // Enqueue email verification notification
    if let Some(code) = email_verification_code {
        let site_settings = db.get_site_settings().await?;
        let template_data = EmailVerification {
            link: format!(
                "{}/verify-email/{code}",
                server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url)
            ),
            theme: site_settings.theme,
        };
        let notification = NewNotification {
            attachments: vec![],
            kind: NotificationKind::EmailVerification,
            recipients: vec![user.user_id],
            template_data: Some(serde_json::to_value(&template_data)?),
        };
        notifications_manager.enqueue(&notification).await?;
        messages.success("Please verify your email to complete the sign up process.");
    }

    // Redirect to the log in page on success
    let log_in_url = get_log_in_url(next_url.as_deref());
    Ok(Redirect::to(&log_in_url).into_response())
}

/// Handler that updates the user's details.
#[instrument(skip_all, err)]
pub(crate) async fn update_user_details(
    messages: Messages,
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    ValidatedFormQs(user_data): ValidatedFormQs<UserDetails>,
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
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    ValidatedForm(mut input): ValidatedForm<templates::auth::UserPassword>,
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
        self.login(user).await.map_err(|e| HandlerError::Auth(e.to_string()))
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
    let Some(state_in_session) = session.remove::<oauth2::CsrfToken>(OAUTH2_CSRF_STATE_KEY).await? else {
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
    let user = match auth.authenticate_oauth2(code, provider).await {
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
    let Some(state_in_session) = session.remove::<oauth2::CsrfToken>(OAUTH2_CSRF_STATE_KEY).await? else {
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
            on_error(format!("{OIDC_AUTHORIZATION_FAILED}: {err}"));
            return Ok(Redirect::to(&log_in_url));
        }
    };

    // Log user in
    auth.log_in(&user).await?;

    // Select the first community and group as selected in the session
    select_first_community_and_group(db, &session, &user.user_id).await?;

    // Track auth provider in the session
    session.insert(AUTH_PROVIDER_KEY, provider).await?;

    let next_url = next_url.as_deref().unwrap_or("/");
    Ok(Redirect::to(next_url))
}

// Other helpers.

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

/// Selects the first available community and group for the user in the session.
pub(crate) async fn select_first_community_and_group(
    db: &DynDB,
    session: &Session,
    user_id: &Uuid,
) -> Result<(), HandlerError> {
    let groups_by_community = db.list_user_groups(user_id).await?;
    if let Some(first_community) = groups_by_community.first() {
        session
            .insert(SELECTED_COMMUNITY_ID_KEY, first_community.community.community_id)
            .await?;
        if let Some(first_group) = first_community.groups.first() {
            session.insert(SELECTED_GROUP_ID_KEY, first_group.group_id).await?;
        }
    } else {
        // User might be a community team member without groups
        let communities = db.list_user_communities(user_id).await?;
        if let Some(first_community) = communities.first() {
            session
                .insert(SELECTED_COMMUNITY_ID_KEY, first_community.community_id)
                .await?;
        }
    }
    Ok(())
}

// Types.

/// Login form data from the user.
#[derive(Debug, Deserialize, Validate)]
pub(crate) struct LoginForm {
    /// Username for authentication.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_S))]
    pub username: String,
    /// Password for authentication.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_S))]
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

/// Check if the user owns any group in the community (from path).
#[instrument(skip_all)]
pub(crate) async fn user_owns_groups_in_path_community(
    State(db): State<DynDB>,
    Path(community_id): Path<Uuid>,
    auth_session: AuthSession,
    request: Request,
    next: Next,
) -> impl IntoResponse {
    // Check if user is logged in
    let Some(user) = auth_session.user else {
        return StatusCode::FORBIDDEN.into_response();
    };

    // Check if the user owns groups in the community
    let Ok(owns) = db.user_owns_groups_in_community(&community_id, &user.user_id).await else {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    };
    if !owns {
        return StatusCode::FORBIDDEN.into_response();
    }

    next.run(request).await.into_response()
}

/// Check if the user owns the community (from path).
#[instrument(skip_all)]
pub(crate) async fn user_owns_path_community(
    State(db): State<DynDB>,
    Path(community_id): Path<Uuid>,
    auth_session: AuthSession,
    request: Request,
    next: Next,
) -> impl IntoResponse {
    // Check if user is logged in
    let Some(user) = auth_session.user else {
        return StatusCode::FORBIDDEN.into_response();
    };

    // Check if the user owns the community
    let Ok(owns) = db.user_owns_community(&community_id, &user.user_id).await else {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    };
    if !owns {
        return StatusCode::FORBIDDEN.into_response();
    }

    next.run(request).await.into_response()
}

/// Check if the user owns the group (from path).
#[instrument(skip_all)]
pub(crate) async fn user_owns_path_group(
    State(db): State<DynDB>,
    Path(group_id): Path<Uuid>,
    auth_session: AuthSession,
    session: Session,
    request: Request,
    next: Next,
) -> impl IntoResponse {
    // Check if user is logged in
    let Some(user) = auth_session.user else {
        return StatusCode::FORBIDDEN.into_response();
    };

    // Get selected community from session
    let community_id = match session.get::<Uuid>(SELECTED_COMMUNITY_ID_KEY).await {
        Ok(Some(community_id)) => community_id,
        Ok(None) => return Redirect::to(USER_DASHBOARD_INVITATIONS_URL).into_response(),
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };

    // Check if the user owns the group
    let Ok(owns) = db.user_owns_group(&community_id, &group_id, &user.user_id).await else {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    };
    if !owns {
        return StatusCode::FORBIDDEN.into_response();
    }

    next.run(request).await.into_response()
}

/// Check if the user owns the selected community (from session).
#[instrument(skip_all)]
pub(crate) async fn user_owns_selected_community(
    State(db): State<DynDB>,
    auth_session: AuthSession,
    session: Session,
    request: Request,
    next: Next,
) -> impl IntoResponse {
    // Check if user is logged in
    let Some(user) = auth_session.user else {
        return StatusCode::FORBIDDEN.into_response();
    };

    // Get selected community from session
    let community_id = match session.get::<Uuid>(SELECTED_COMMUNITY_ID_KEY).await {
        Ok(Some(community_id)) => community_id,
        Ok(None) => return Redirect::to(USER_DASHBOARD_INVITATIONS_URL).into_response(),
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };

    // Check if the user owns the community
    let Ok(owns) = db.user_owns_community(&community_id, &user.user_id).await else {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    };
    if !owns {
        return StatusCode::FORBIDDEN.into_response();
    }

    // Store selected community context for downstream extractors
    let mut request = request;
    request.extensions_mut().insert(SelectedCommunityId(community_id));

    next.run(request).await.into_response()
}

/// Check if the user owns the selected group (from session).
#[instrument(skip_all)]
pub(crate) async fn user_owns_selected_group(
    State(db): State<DynDB>,
    auth_session: AuthSession,
    session: Session,
    request: Request,
    next: Next,
) -> impl IntoResponse {
    // Check if user is logged in
    let Some(user) = auth_session.user else {
        return StatusCode::FORBIDDEN.into_response();
    };

    // Get selected community and group from session
    let community_id = match session.get::<Uuid>(SELECTED_COMMUNITY_ID_KEY).await {
        Ok(Some(community_id)) => community_id,
        Ok(None) => return Redirect::to(USER_DASHBOARD_INVITATIONS_URL).into_response(),
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };
    let group_id = match session.get::<Uuid>(SELECTED_GROUP_ID_KEY).await {
        Ok(Some(group_id)) => group_id,
        Ok(None) => return Redirect::to(USER_DASHBOARD_INVITATIONS_URL).into_response(),
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };

    // Check if the user owns the group
    let Ok(owns) = db.user_owns_group(&community_id, &group_id, &user.user_id).await else {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    };
    if !owns {
        return StatusCode::FORBIDDEN.into_response();
    }

    // Store selected community and group context for downstream extractors
    let mut request = request;
    request.extensions_mut().insert(SelectedCommunityId(community_id));
    request.extensions_mut().insert(SelectedGroupId(group_id));

    next.run(request).await.into_response()
}

// Tests.

#[cfg(test)]
mod tests {
    use std::{collections::HashMap, sync::Arc};

    use anyhow::anyhow;
    use axum::extract::Query;
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
        db::{DynDB, mock::MockDB},
        handlers::{
            extractors::{OAuth2, Oidc},
            tests::*,
        },
        router::{CACHE_CONTROL_NO_CACHE, State, serde_qs_config},
        services::{
            images::MockImageStorage,
            notifications::{MockNotificationsManager, NotificationKind},
        },
        templates::notifications::EmailVerification as EmailVerificationTemplate,
    };

    use super::*;

    #[tokio::test]
    async fn test_log_in_page_success() {
        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_site_settings()
            .times(1)
            .returning(|| Ok(sample_site_settings()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri(LOG_IN_URL)
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
            &HeaderValue::from_static(CACHE_CONTROL_NO_CACHE),
        );
        assert!(!bytes.is_empty());
    }

    #[tokio::test]
    async fn test_log_in_page_redirects_when_authenticated() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

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
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri(LOG_IN_URL)
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
        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_site_settings()
            .times(1)
            .returning(|| Ok(sample_site_settings()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri(SIGN_UP_URL)
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
            &HeaderValue::from_static(CACHE_CONTROL_NO_CACHE),
        );
        assert!(!bytes.is_empty());
    }

    #[tokio::test]
    async fn test_sign_up_page_redirects_when_authenticated() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

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
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri(SIGN_UP_URL)
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
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

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
        let router = TestRouterBuilder::new(db, nm).build().await;
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
            &HeaderValue::from_static(CACHE_CONTROL_NO_CACHE),
        );
        assert!(!bytes.is_empty());
    }

    #[tokio::test]
    async fn test_dashboard_community_redirects_to_user_invitations_when_selected_community_is_missing() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

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
        db.expect_user_owns_community().times(0);

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/community")
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
            &HeaderValue::from_static(USER_DASHBOARD_INVITATIONS_URL),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_dashboard_group_redirects_to_user_invitations_when_selected_ids_are_missing() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

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
        db.expect_user_owns_group().times(0);

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/group")
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
            &HeaderValue::from_static(USER_DASHBOARD_INVITATIONS_URL),
        );
        assert!(bytes.is_empty());
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
        db.expect_get_user_by_username()
            .times(1)
            .withf(move |username| username == "test-user")
            .returning(move |_| {
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
            .returning(move |_| Ok(sample_user_groups_by_community(community_id, group_id)));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router
        let mut server_cfg = HttpServerConfig::default();
        server_cfg.login.email = true;
        let router = TestRouterBuilder::new(db, nm)
            .with_server_cfg(server_cfg)
            .build()
            .await;

        // Setup request
        let request = Request::builder()
            .method("POST")
            .uri("/log-in?next_url=%2Fdashboard")
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
        let session_id = session::Id::default();
        let session_record = empty_session_record(session_id);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_username()
            .times(1)
            .withf(move |username| username == "test-user")
            .returning(|_| Ok(None));
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
        let mut server_cfg = HttpServerConfig::default();
        server_cfg.login.email = true;
        let router = TestRouterBuilder::new(db, nm)
            .with_server_cfg(server_cfg)
            .build()
            .await;

        // Setup request
        let request = Request::builder()
            .method("POST")
            .uri("/log-in")
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
    async fn test_log_in_validation_error() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let session_record = empty_session_record(session_id);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_username().times(0);
        db.expect_update_session()
            .times(1)
            .withf(|record| message_matches(record, "username: value cannot be empty or whitespace-only\n"))
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router
        let mut server_cfg = HttpServerConfig::default();
        server_cfg.login.email = true;
        let router = TestRouterBuilder::new(db, nm)
            .with_server_cfg(server_cfg)
            .build()
            .await;

        // Setup request (username is whitespace only - validation should fail)
        let request = Request::builder()
            .method("POST")
            .uri("/log-in")
            .header(COOKIE, format!("id={session_id}"))
            .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
            .body(Body::from("username=+++&password=secret"))
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
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

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
        let router = TestRouterBuilder::new(db, nm).build().await;
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
        let router = TestRouterBuilder::new(db, nm).build().await;
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
        let session_id = session::Id::default();
        let session_record = empty_session_record(session_id);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_update_session()
            .times(1)
            .withf(move |record| message_matches(record, "OAuth2 authorization failed"))
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue().times(0);

        // Setup router
        let mut server_cfg = HttpServerConfig::default();
        server_cfg.login.github = true;
        server_cfg.oauth2.insert(
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
        let router = TestRouterBuilder::new(db, nm)
            .with_server_cfg(server_cfg)
            .build()
            .await;

        // Setup request
        let request = Request::builder()
            .method("GET")
            .uri("/log-in/oauth2/github/callback?code=test-code&state=test-state")
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
        db.expect_update_session()
            .times(1)
            .withf(move |record| message_matches(record, "OAuth2 authorization failed"))
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue().times(0);

        // Setup router
        let mut server_cfg = HttpServerConfig::default();
        server_cfg.login.github = true;
        server_cfg.oauth2.insert(
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
        let router = TestRouterBuilder::new(db, nm)
            .with_server_cfg(server_cfg)
            .build()
            .await;

        // Setup request
        let request = Request::builder()
            .method("GET")
            .uri("/log-in/oauth2/github/callback?code=test-code&state=state-in-request")
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
    async fn test_oauth2_callback_authorization_error() {
        // Setup in-memory session
        let store = Arc::new(MemoryStore::default());
        let session = Session::new(None, store, None);
        session
            .insert(OAUTH2_CSRF_STATE_KEY, "state-in-session")
            .await
            .unwrap();
        session
            .insert(NEXT_URL_KEY, Some("/dashboard".to_string()))
            .await
            .unwrap();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_list_user_groups().times(0);

        // Setup callback auth mock
        let mut callback_auth = MockCallbackAuth {
            login_called: false,
            login_result: Some(Ok(())),
            oidc_result: None,
            oauth2_result: Some(Err("oauth2 auth error".to_string())),
        };
        let db: DynDB = Arc::new(db);

        // Execute helper
        let error_message = std::sync::Arc::new(std::sync::Mutex::new(None));
        let captured_error_message = error_message.clone();
        let redirect = oauth2_callback_with_auth(
            &mut callback_auth,
            session.clone(),
            &db,
            OAuth2Provider::GitHub,
            "test-code".to_string(),
            oauth2::CsrfToken::new("state-in-session".to_string()),
            move |message| {
                let mut guard = captured_error_message.lock().unwrap();
                *guard = Some(message);
            },
        )
        .await
        .unwrap();

        // Check callback result and side effects
        let response = redirect.into_response();
        let selected_community_id: Option<Uuid> = session.get(SELECTED_COMMUNITY_ID_KEY).await.unwrap();
        let selected_group_id: Option<Uuid> = session.get(SELECTED_GROUP_ID_KEY).await.unwrap();
        assert_eq!(response.status(), StatusCode::SEE_OTHER);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("/log-in?next_url=%2Fdashboard"),
        );
        assert_eq!(
            *error_message.lock().unwrap(),
            Some("OAuth2 authorization failed: oauth2 auth error".to_string()),
        );
        assert!(!callback_auth.login_called);
        assert_eq!(selected_community_id, None);
        assert_eq!(selected_group_id, None);
    }

    #[tokio::test]
    async fn test_oauth2_callback_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let groups = sample_user_groups_by_community(community_id, group_id);

        // Setup in-memory session
        let store = Arc::new(MemoryStore::default());
        let session = Session::new(None, store, None);
        session
            .insert(OAUTH2_CSRF_STATE_KEY, "state-in-session")
            .await
            .unwrap();
        session
            .insert(NEXT_URL_KEY, Some("/dashboard".to_string()))
            .await
            .unwrap();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_list_user_groups()
            .times(1)
            .withf(move |uid| uid == &user_id)
            .returning(move |_| Ok(groups.clone()));

        // Setup callback auth mock
        let mut callback_auth = MockCallbackAuth {
            login_called: false,
            login_result: Some(Ok(())),
            oidc_result: None,
            oauth2_result: Some(Ok(Some(sample_auth_user(user_id, &auth_hash)))),
        };
        let db: DynDB = Arc::new(db);

        // Execute helper
        let redirect = oauth2_callback_with_auth(
            &mut callback_auth,
            session.clone(),
            &db,
            OAuth2Provider::GitHub,
            "test-code".to_string(),
            oauth2::CsrfToken::new("state-in-session".to_string()),
            |_| {
                panic!("oauth2 callback success should not emit an error message");
            },
        )
        .await
        .unwrap();

        // Check callback result and side effects
        let response = redirect.into_response();
        let selected_community_id: Option<Uuid> = session.get(SELECTED_COMMUNITY_ID_KEY).await.unwrap();
        let selected_group_id: Option<Uuid> = session.get(SELECTED_GROUP_ID_KEY).await.unwrap();
        assert_eq!(response.status(), StatusCode::SEE_OTHER);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("/dashboard"),
        );
        assert!(callback_auth.login_called);
        assert_eq!(selected_community_id, Some(community_id));
        assert_eq!(selected_group_id, Some(group_id));
    }

    #[tokio::test]
    async fn test_oauth2_callback_returns_error_when_provider_is_not_configured() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let mut session_record = empty_session_record(session_id);
        session_record
            .data
            .insert(OAUTH2_CSRF_STATE_KEY.to_string(), json!("state-in-session"));
        session_record
            .data
            .insert(NEXT_URL_KEY.to_string(), json!("/dashboard"));

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_update_session()
            .times(1)
            .withf(move |record| {
                message_matches(record, "OAuth2 authorization failed: oauth2 provider not found")
            })
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue().times(0);

        // Setup router
        let mut server_cfg = HttpServerConfig::default();
        server_cfg.login.github = true;
        let router = TestRouterBuilder::new(db, nm)
            .with_server_cfg(server_cfg)
            .build()
            .await;

        // Setup request
        let request = Request::builder()
            .method("GET")
            .uri("/log-in/oauth2/github/callback?code=test-code&state=state-in-session")
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
            &HeaderValue::from_static("/log-in?next_url=%2Fdashboard"),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_oauth2_redirect_success() {
        // Setup session and form input
        let store = Arc::new(MemoryStore::default());
        let session = Session::new(None, store, None);
        let query = Query(NextUrl {
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
        let response = oauth2_redirect(session.clone(), OAuth2(Arc::new(provider)), query)
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
        db.expect_update_session()
            .times(1)
            .withf(move |record| message_matches(record, "OpenID Connect authorization failed"))
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue().times(0);

        // Setup router
        let mut server_cfg = HttpServerConfig::default();
        server_cfg.login.linuxfoundation = true;
        let router = TestRouterBuilder::new(db, nm)
            .with_server_cfg(server_cfg)
            .build()
            .await;

        // Setup request
        let request = Request::builder()
            .method("GET")
            .uri("/log-in/oidc/linuxfoundation/callback?code=test-code&state=state-in-session")
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
        let session_id = session::Id::default();
        let session_record = empty_session_record(session_id);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_update_session()
            .times(1)
            .withf(move |record| message_matches(record, "OpenID Connect authorization failed"))
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue().times(0);

        // Setup router
        let mut server_cfg = HttpServerConfig::default();
        server_cfg.login.linuxfoundation = true;
        let router = TestRouterBuilder::new(db, nm)
            .with_server_cfg(server_cfg)
            .build()
            .await;

        // Setup request
        let request = Request::builder()
            .method("GET")
            .uri("/log-in/oidc/linuxfoundation/callback?code=test-code&state=test-state")
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
        db.expect_update_session()
            .times(1)
            .withf(move |record| message_matches(record, "OpenID Connect authorization failed"))
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue().times(0);

        // Setup router
        let mut server_cfg = HttpServerConfig::default();
        server_cfg.login.linuxfoundation = true;
        let router = TestRouterBuilder::new(db, nm)
            .with_server_cfg(server_cfg)
            .build()
            .await;

        // Setup request
        let request = Request::builder()
            .method("GET")
            .uri("/log-in/oidc/linuxfoundation/callback?code=test-code&state=state-in-request")
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
    async fn test_oidc_callback_authorization_error() {
        // Setup in-memory session
        let store = Arc::new(MemoryStore::default());
        let session = Session::new(None, store, None);
        session
            .insert(OAUTH2_CSRF_STATE_KEY, "state-in-session")
            .await
            .unwrap();
        session.insert(OIDC_NONCE_KEY, "nonce-in-session").await.unwrap();
        session
            .insert(NEXT_URL_KEY, Some("/dashboard".to_string()))
            .await
            .unwrap();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_list_user_groups().times(0);

        // Setup callback auth mock
        let mut callback_auth = MockCallbackAuth {
            login_called: false,
            login_result: Some(Ok(())),
            oidc_result: Some(Err("oidc auth error".to_string())),
            oauth2_result: None,
        };
        let db: DynDB = Arc::new(db);

        // Execute helper
        let error_message = std::sync::Arc::new(std::sync::Mutex::new(None));
        let captured_error_message = error_message.clone();
        let redirect = oidc_callback_with_auth(
            &mut callback_auth,
            session.clone(),
            &db,
            OidcProvider::LinuxFoundation,
            "test-code".to_string(),
            oauth2::CsrfToken::new("state-in-session".to_string()),
            move |message| {
                let mut guard = captured_error_message.lock().unwrap();
                *guard = Some(message);
            },
        )
        .await
        .unwrap();

        // Check callback result and side effects
        let response = redirect.into_response();
        let auth_provider: Option<OidcProvider> = session.get(AUTH_PROVIDER_KEY).await.unwrap();
        let selected_community_id: Option<Uuid> = session.get(SELECTED_COMMUNITY_ID_KEY).await.unwrap();
        let selected_group_id: Option<Uuid> = session.get(SELECTED_GROUP_ID_KEY).await.unwrap();
        assert_eq!(response.status(), StatusCode::SEE_OTHER);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("/log-in?next_url=%2Fdashboard"),
        );
        assert_eq!(
            *error_message.lock().unwrap(),
            Some("OpenID Connect authorization failed: oidc auth error".to_string()),
        );
        assert!(!callback_auth.login_called);
        assert_eq!(auth_provider, None);
        assert_eq!(selected_community_id, None);
        assert_eq!(selected_group_id, None);
    }

    #[tokio::test]
    async fn test_oidc_callback_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let groups = sample_user_groups_by_community(community_id, group_id);

        // Setup in-memory session
        let store = Arc::new(MemoryStore::default());
        let session = Session::new(None, store, None);
        session
            .insert(OAUTH2_CSRF_STATE_KEY, "state-in-session")
            .await
            .unwrap();
        session.insert(OIDC_NONCE_KEY, "nonce-in-session").await.unwrap();
        session
            .insert(NEXT_URL_KEY, Some("/dashboard".to_string()))
            .await
            .unwrap();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_list_user_groups()
            .times(1)
            .withf(move |uid| uid == &user_id)
            .returning(move |_| Ok(groups.clone()));

        // Setup callback auth mock
        let mut callback_auth = MockCallbackAuth {
            login_called: false,
            login_result: Some(Ok(())),
            oidc_result: Some(Ok(Some(sample_auth_user(user_id, &auth_hash)))),
            oauth2_result: None,
        };
        let db: DynDB = Arc::new(db);

        // Execute helper
        let redirect = oidc_callback_with_auth(
            &mut callback_auth,
            session.clone(),
            &db,
            OidcProvider::LinuxFoundation,
            "test-code".to_string(),
            oauth2::CsrfToken::new("state-in-session".to_string()),
            |_| {
                panic!("oidc callback success should not emit an error message");
            },
        )
        .await
        .unwrap();

        // Check callback result and side effects
        let response = redirect.into_response();
        let auth_provider: Option<OidcProvider> = session.get(AUTH_PROVIDER_KEY).await.unwrap();
        let selected_community_id: Option<Uuid> = session.get(SELECTED_COMMUNITY_ID_KEY).await.unwrap();
        let selected_group_id: Option<Uuid> = session.get(SELECTED_GROUP_ID_KEY).await.unwrap();
        assert_eq!(response.status(), StatusCode::SEE_OTHER);
        assert_eq!(
            response.headers().get(LOCATION).unwrap(),
            &HeaderValue::from_static("/dashboard"),
        );
        assert!(callback_auth.login_called);
        assert_eq!(auth_provider, Some(OidcProvider::LinuxFoundation));
        assert_eq!(selected_community_id, Some(community_id));
        assert_eq!(selected_group_id, Some(group_id));
    }

    #[tokio::test]
    async fn test_oidc_callback_returns_error_when_provider_is_not_configured() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let mut session_record = empty_session_record(session_id);
        session_record
            .data
            .insert(OAUTH2_CSRF_STATE_KEY.to_string(), json!("state-in-session"));
        session_record
            .data
            .insert(OIDC_NONCE_KEY.to_string(), json!("nonce-in-session"));
        session_record
            .data
            .insert(NEXT_URL_KEY.to_string(), json!("/dashboard"));

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_update_session()
            .times(1)
            .withf(move |record| {
                message_matches(
                    record,
                    "OpenID Connect authorization failed: oidc provider not found",
                )
            })
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue().times(0);

        // Setup router
        let mut server_cfg = HttpServerConfig::default();
        server_cfg.login.linuxfoundation = true;
        let router = TestRouterBuilder::new(db, nm)
            .with_server_cfg(server_cfg)
            .build()
            .await;

        // Setup request
        let request = Request::builder()
            .method("GET")
            .uri("/log-in/oidc/linuxfoundation/callback?code=test-code&state=state-in-session")
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
            &HeaderValue::from_static("/log-in?next_url=%2Fdashboard"),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_oidc_redirect_success() {
        // Setup session and form input
        let store = Arc::new(MemoryStore::default());
        let session = Session::new(None, store, None);
        let query = Query(NextUrl {
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
        let response = oidc_redirect(session.clone(), Oidc(Arc::new(provider)), query)
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
        let session_id = session::Id::default();
        let session_record = empty_session_record(session_id);
        let email_verification_code = Uuid::new_v4();
        let user = sample_auth_user(Uuid::new_v4(), "hash");
        let user_for_notifications = user.clone();
        let user_for_db = user;

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        let site_settings = sample_site_settings();
        let site_settings_for_notifications = site_settings.clone();
        db.expect_sign_up_user()
            .times(1)
            .withf(move |summary, verify| {
                !matches!(summary.password.as_deref(), Some("secret-password")) && !verify
            })
            .returning({
                let user = user_for_db;
                move |_, _| Ok((user.clone(), Some(email_verification_code)))
            });
        db.expect_get_site_settings()
            .times(1)
            .returning(move || Ok(site_settings.clone()));
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
                    && notification.recipients == vec![user_for_notifications.user_id]
                    && notification.template_data.as_ref().is_some_and(|value| {
                        serde_json::from_value::<EmailVerificationTemplate>(value.clone())
                            .map(|template| {
                                template.link
                                    == format!("https://app.example/verify-email/{email_verification_code}")
                                    && template.theme.primary_color
                                        == site_settings_for_notifications.theme.primary_color
                            })
                            .unwrap_or(false)
                    })
            })
            .returning(|_| Box::pin(async { Ok(()) }));

        // Setup router
        let server_cfg = HttpServerConfig {
            base_url: "https://app.example".to_string(),
            login: LoginOptions {
                email: true,
                ..Default::default()
            },
            ..Default::default()
        };
        let router = TestRouterBuilder::new(db, nm)
            .with_server_cfg(server_cfg)
            .build()
            .await;

        // Setup request
        let form = "email=test%40example.test&name=Test+User&username=test-user&password=secret-password";
        let request = Request::builder()
            .method("POST")
            .uri("/sign-up?next_url=%2Fwelcome")
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
        let session_id = session::Id::default();
        let session_record = empty_session_record(session_id);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_sign_up_user().times(0);

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue().times(0);

        // Setup router
        let mut server_cfg = HttpServerConfig::default();
        server_cfg.login.email = true;
        let router = TestRouterBuilder::new(db, nm)
            .with_server_cfg(server_cfg)
            .build()
            .await;

        // Setup request (password not provided)
        let form = "email=test%40example.test&name=Test+User&username=test-user";
        let request = Request::builder()
            .method("POST")
            .uri("/sign-up")
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
        let session_id = session::Id::default();
        let session_record = empty_session_record(session_id);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_sign_up_user()
            .times(1)
            .returning(|_, _| Err(anyhow!("db error")));
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
        let mut server_cfg = HttpServerConfig::default();
        server_cfg.login.email = true;
        let router = TestRouterBuilder::new(db, nm)
            .with_server_cfg(server_cfg)
            .build()
            .await;

        // Setup request
        let form = "email=test%40example.test&name=Test+User&username=test-user&password=secretpw";
        let request = Request::builder()
            .method("POST")
            .uri("/sign-up")
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
    async fn test_sign_up_validation_error() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let session_record = empty_session_record(session_id);

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_sign_up_user().times(0);
        db.expect_update_session()
            .times(1)
            .withf(|record| {
                message_matches(
                    record,
                    "email: not a valid email: value is missing `@`\npassword: length is lower than 8\n",
                )
            })
            .returning(|_| Ok(()));

        // Setup notifications manager mock
        let mut nm = MockNotificationsManager::new();
        nm.expect_enqueue().times(0);

        // Setup router
        let mut server_cfg = HttpServerConfig::default();
        server_cfg.login.email = true;
        let router = TestRouterBuilder::new(db, nm)
            .with_server_cfg(server_cfg)
            .build()
            .await;

        // Setup request (invalid email - validation should fail)
        let form = "email=invalid-email&name=Test+User&username=test-user&password=secret";
        let request = Request::builder()
            .method("POST")
            .uri("/sign-up")
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
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

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
        let router = TestRouterBuilder::new(db, nm).build().await;
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
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

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
        let router = TestRouterBuilder::new(db, nm).build().await;
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
    async fn test_update_user_details_returns_error_on_db_failure() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

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
            .returning(|_, _| Err(anyhow!("db error")));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
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
        assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_update_user_password_success() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
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
        let router = TestRouterBuilder::new(db, nm).build().await;
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
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
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
        let router = TestRouterBuilder::new(db, nm).build().await;
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
    async fn test_update_user_password_returns_bad_request_when_hash_is_missing() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

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
            .returning(|_| Ok(None));
        db.expect_update_user_password().times(0);

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
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
        assert_eq!(parts.status, StatusCode::BAD_REQUEST);
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_update_user_password_returns_error_on_db_failure() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
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
            .returning(|_, _| Err(anyhow!("db error")));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
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
        assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
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
        let mut server_cfg = HttpServerConfig::default();
        server_cfg.login.email = true;
        let router = TestRouterBuilder::new(db, nm)
            .with_server_cfg(server_cfg)
            .build()
            .await;
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
        let mut server_cfg = HttpServerConfig::default();
        server_cfg.login.email = true;
        let router = TestRouterBuilder::new(db, nm)
            .with_server_cfg(server_cfg)
            .build()
            .await;
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
    async fn test_select_first_community_and_group_selects_community_when_user_has_no_groups() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let user_id = Uuid::new_v4();

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_list_user_groups()
            .times(1)
            .withf(move |uid| *uid == user_id)
            .returning(|_| Ok(vec![]));
        db.expect_list_user_communities()
            .times(1)
            .withf(move |uid| *uid == user_id)
            .returning(move |_| Ok(vec![sample_community_summary(community_id)]));

        // Setup in-memory session
        let db: DynDB = Arc::new(db);
        let store = Arc::new(MemoryStore::default());
        let session = Session::new(None, store, None);

        // Execute helper
        select_first_community_and_group(&db, &session, &user_id)
            .await
            .expect("helper should select first available community");

        // Check session data matches expectations
        let selected_community_id: Option<Uuid> = session.get(SELECTED_COMMUNITY_ID_KEY).await.unwrap();
        let selected_group_id: Option<Uuid> = session.get(SELECTED_GROUP_ID_KEY).await.unwrap();
        assert_eq!(selected_community_id, Some(community_id));
        assert_eq!(selected_group_id, None);
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
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

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
        let server_cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            server_cfg: server_cfg.clone(),
            db: db.clone(),
            image_storage: Arc::new(MockImageStorage::new()),
            meetings_cfg: None,
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs_config(),
        };
        let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
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
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

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
        let server_cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            server_cfg: server_cfg.clone(),
            db: db.clone(),
            image_storage: Arc::new(MockImageStorage::new()),
            meetings_cfg: None,
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs_config(),
        };
        let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
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
        let server_cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            server_cfg: server_cfg.clone(),
            db: db.clone(),
            image_storage: Arc::new(MockImageStorage::new()),
            meetings_cfg: None,
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs_config(),
        };
        let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
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
    async fn test_user_owns_path_community_allows_request() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let community_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

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
        db.expect_user_owns_community()
            .times(1)
            .withf(move |cid, uid| *cid == community_id && *uid == user_id)
            .returning(|_, _| Ok(true));

        // Setup router
        let server_cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            server_cfg: server_cfg.clone(),
            db: db.clone(),
            image_storage: Arc::new(MockImageStorage::new()),
            meetings_cfg: None,
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs_config(),
        };
        let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route("/{community_id}/protected", get(|| async { StatusCode::OK }))
            .layer(middleware::from_fn_with_state(
                state.clone(),
                user_owns_path_community,
            ))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri(format!("/{community_id}/protected"))
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
    async fn test_user_owns_path_community_forbidden_when_not_owner() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let community_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

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
        db.expect_user_owns_community()
            .times(1)
            .withf(move |cid, uid| *cid == community_id && *uid == user_id)
            .returning(|_, _| Ok(false));

        // Setup router
        let server_cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            server_cfg: server_cfg.clone(),
            db: db.clone(),
            image_storage: Arc::new(MockImageStorage::new()),
            meetings_cfg: None,
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs_config(),
        };
        let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route("/{community_id}/protected", get(|| async { StatusCode::OK }))
            .layer(middleware::from_fn_with_state(
                state.clone(),
                user_owns_path_community,
            ))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri(format!("/{community_id}/protected"))
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
    async fn test_user_owns_path_community_returns_error_on_db_failure() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let community_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

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
        db.expect_user_owns_community()
            .times(1)
            .withf(move |cid, uid| *cid == community_id && *uid == user_id)
            .returning(|_, _| Err(anyhow!("db error")));

        // Setup router
        let server_cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            server_cfg: server_cfg.clone(),
            db: db.clone(),
            image_storage: Arc::new(MockImageStorage::new()),
            meetings_cfg: None,
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs_config(),
        };
        let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route("/{community_id}/protected", get(|| async { StatusCode::OK }))
            .layer(middleware::from_fn_with_state(
                state.clone(),
                user_owns_path_community,
            ))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri(format!("/{community_id}/protected"))
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
    async fn test_user_owns_groups_in_path_community_allows_request() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let community_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

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
        db.expect_user_owns_groups_in_community()
            .times(1)
            .withf(move |cid, uid| *cid == community_id && *uid == user_id)
            .returning(|_, _| Ok(true));

        // Setup router
        let server_cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            server_cfg: server_cfg.clone(),
            db: db.clone(),
            image_storage: Arc::new(MockImageStorage::new()),
            meetings_cfg: None,
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs_config(),
        };
        let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route(
                "/community/{community_id}/select",
                get(|| async { StatusCode::OK }),
            )
            .layer(middleware::from_fn_with_state(
                state.clone(),
                user_owns_groups_in_path_community,
            ))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri(format!("/community/{community_id}/select"))
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
    async fn test_user_owns_groups_in_path_community_forbidden_when_not_owner() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let community_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

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
        db.expect_user_owns_groups_in_community()
            .times(1)
            .withf(move |cid, uid| *cid == community_id && *uid == user_id)
            .returning(|_, _| Ok(false));

        // Setup router
        let server_cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            server_cfg: server_cfg.clone(),
            db: db.clone(),
            image_storage: Arc::new(MockImageStorage::new()),
            meetings_cfg: None,
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs_config(),
        };
        let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route(
                "/community/{community_id}/select",
                get(|| async { StatusCode::OK }),
            )
            .layer(middleware::from_fn_with_state(
                state.clone(),
                user_owns_groups_in_path_community,
            ))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri(format!("/community/{community_id}/select"))
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
    async fn test_user_owns_groups_in_path_community_returns_error_on_db_failure() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let community_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

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
        db.expect_user_owns_groups_in_community()
            .times(1)
            .withf(move |cid, uid| *cid == community_id && *uid == user_id)
            .returning(|_, _| Err(anyhow!("db error")));

        // Setup router
        let server_cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            server_cfg: server_cfg.clone(),
            db: db.clone(),
            image_storage: Arc::new(MockImageStorage::new()),
            meetings_cfg: None,
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs_config(),
        };
        let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route(
                "/community/{community_id}/select",
                get(|| async { StatusCode::OK }),
            )
            .layer(middleware::from_fn_with_state(
                state.clone(),
                user_owns_groups_in_path_community,
            ))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri(format!("/community/{community_id}/select"))
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
    async fn test_user_owns_path_group_allows_request() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(community_id), None);

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
        db.expect_user_owns_group()
            .times(1)
            .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(true));

        // Setup router
        let server_cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            server_cfg: server_cfg.clone(),
            db: db.clone(),
            image_storage: Arc::new(MockImageStorage::new()),
            meetings_cfg: None,
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs_config(),
        };
        let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route("/groups/{group_id}", get(|| async { StatusCode::OK }))
            .layer(middleware::from_fn_with_state(
                state.clone(),
                user_owns_path_group,
            ))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri(format!("/groups/{group_id}"))
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
    async fn test_user_owns_path_group_forbidden_when_not_owner() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(community_id), None);

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
        db.expect_user_owns_group()
            .times(1)
            .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(false));

        // Setup router
        let server_cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            server_cfg: server_cfg.clone(),
            db: db.clone(),
            image_storage: Arc::new(MockImageStorage::new()),
            meetings_cfg: None,
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs_config(),
        };
        let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route("/groups/{group_id}", get(|| async { StatusCode::OK }))
            .layer(middleware::from_fn_with_state(
                state.clone(),
                user_owns_path_group,
            ))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri(format!("/groups/{group_id}"))
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
    async fn test_user_owns_path_group_returns_error_on_db_failure() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(community_id), None);

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
        db.expect_user_owns_group()
            .times(1)
            .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Err(anyhow!("db error")));

        // Setup router
        let server_cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            server_cfg: server_cfg.clone(),
            db: db.clone(),
            image_storage: Arc::new(MockImageStorage::new()),
            meetings_cfg: None,
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs_config(),
        };
        let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route("/groups/{group_id}", get(|| async { StatusCode::OK }))
            .layer(middleware::from_fn_with_state(
                state.clone(),
                user_owns_path_group,
            ))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri(format!("/groups/{group_id}"))
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
    async fn test_user_owns_path_group_redirects_when_selected_community_is_missing() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

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
        db.expect_user_owns_group().times(0);

        // Setup router
        let server_cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            server_cfg: server_cfg.clone(),
            db: db.clone(),
            image_storage: Arc::new(MockImageStorage::new()),
            meetings_cfg: None,
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs_config(),
        };
        let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route("/groups/{group_id}", get(|| async { StatusCode::OK }))
            .layer(middleware::from_fn_with_state(
                state.clone(),
                user_owns_path_group,
            ))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri(format!("/groups/{group_id}"))
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
            &HeaderValue::from_static(USER_DASHBOARD_INVITATIONS_URL),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_user_owns_selected_community_allows_request() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let community_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(community_id), None);

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
        db.expect_user_owns_community()
            .times(1)
            .withf(move |cid, uid| *cid == community_id && *uid == user_id)
            .returning(|_, _| Ok(true));

        // Setup router
        let server_cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            server_cfg: server_cfg.clone(),
            db: db.clone(),
            image_storage: Arc::new(MockImageStorage::new()),
            meetings_cfg: None,
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs_config(),
        };
        let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route("/protected", get(|| async { StatusCode::OK }))
            .layer(middleware::from_fn_with_state(
                state.clone(),
                user_owns_selected_community,
            ))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri("/protected")
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
    async fn test_user_owns_selected_community_forbidden_when_not_owner() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let community_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(community_id), None);

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
        db.expect_user_owns_community()
            .times(1)
            .withf(move |cid, uid| *cid == community_id && *uid == user_id)
            .returning(|_, _| Ok(false));

        // Setup router
        let server_cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            server_cfg: server_cfg.clone(),
            db: db.clone(),
            image_storage: Arc::new(MockImageStorage::new()),
            meetings_cfg: None,
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs_config(),
        };
        let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route("/protected", get(|| async { StatusCode::OK }))
            .layer(middleware::from_fn_with_state(
                state.clone(),
                user_owns_selected_community,
            ))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri("/protected")
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
    async fn test_user_owns_selected_community_returns_error_on_db_failure() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let community_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(community_id), None);

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
        db.expect_user_owns_community()
            .times(1)
            .withf(move |cid, uid| *cid == community_id && *uid == user_id)
            .returning(|_, _| Err(anyhow!("db error")));

        // Setup router
        let server_cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            server_cfg: server_cfg.clone(),
            db: db.clone(),
            image_storage: Arc::new(MockImageStorage::new()),
            meetings_cfg: None,
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs_config(),
        };
        let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route("/protected", get(|| async { StatusCode::OK }))
            .layer(middleware::from_fn_with_state(
                state.clone(),
                user_owns_selected_community,
            ))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri("/protected")
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
    async fn test_user_owns_selected_community_redirects_when_selected_community_is_missing() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

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
        db.expect_user_owns_community().times(0);

        // Setup router
        let server_cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            server_cfg: server_cfg.clone(),
            db: db.clone(),
            image_storage: Arc::new(MockImageStorage::new()),
            meetings_cfg: None,
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs_config(),
        };
        let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route("/protected", get(|| async { StatusCode::OK }))
            .layer(middleware::from_fn_with_state(
                state.clone(),
                user_owns_selected_community,
            ))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri("/protected")
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
            &HeaderValue::from_static(USER_DASHBOARD_INVITATIONS_URL),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_user_owns_selected_group_allows_request() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(
            session_id,
            user_id,
            &auth_hash,
            Some(community_id),
            Some(group_id),
        );

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
        db.expect_user_owns_group()
            .times(1)
            .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(true));

        // Setup router
        let server_cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            server_cfg: server_cfg.clone(),
            db: db.clone(),
            image_storage: Arc::new(MockImageStorage::new()),
            meetings_cfg: None,
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs_config(),
        };
        let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route("/protected", get(|| async { StatusCode::OK }))
            .layer(middleware::from_fn_with_state(
                state.clone(),
                user_owns_selected_group,
            ))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri("/protected")
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
    async fn test_user_owns_selected_group_forbidden_when_not_owner() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(
            session_id,
            user_id,
            &auth_hash,
            Some(community_id),
            Some(group_id),
        );

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
        db.expect_user_owns_group()
            .times(1)
            .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Ok(false));

        // Setup router
        let server_cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            server_cfg: server_cfg.clone(),
            db: db.clone(),
            image_storage: Arc::new(MockImageStorage::new()),
            meetings_cfg: None,
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs_config(),
        };
        let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route("/protected", get(|| async { StatusCode::OK }))
            .layer(middleware::from_fn_with_state(
                state.clone(),
                user_owns_selected_group,
            ))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri("/protected")
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
    async fn test_user_owns_selected_group_returns_error_on_db_failure() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(
            session_id,
            user_id,
            &auth_hash,
            Some(community_id),
            Some(group_id),
        );

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
        db.expect_user_owns_group()
            .times(1)
            .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
            .returning(|_, _, _| Err(anyhow!("db error")));

        // Setup router
        let server_cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            server_cfg: server_cfg.clone(),
            db: db.clone(),
            image_storage: Arc::new(MockImageStorage::new()),
            meetings_cfg: None,
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs_config(),
        };
        let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route("/protected", get(|| async { StatusCode::OK }))
            .layer(middleware::from_fn_with_state(
                state.clone(),
                user_owns_selected_group,
            ))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri("/protected")
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
    async fn test_user_owns_selected_group_redirects_when_selected_group_is_missing() {
        // Setup identifiers and data structures
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let community_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, Some(community_id), None);

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
        db.expect_user_owns_group().times(0);

        // Setup router
        let server_cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            server_cfg: server_cfg.clone(),
            db: db.clone(),
            image_storage: Arc::new(MockImageStorage::new()),
            meetings_cfg: None,
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs_config(),
        };
        let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route("/protected", get(|| async { StatusCode::OK }))
            .layer(middleware::from_fn_with_state(
                state.clone(),
                user_owns_selected_group,
            ))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri("/protected")
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
            &HeaderValue::from_static(USER_DASHBOARD_INVITATIONS_URL),
        );
        assert!(bytes.is_empty());
    }

    #[tokio::test]
    async fn test_user_owns_groups_in_path_community_forbidden_when_not_logged_in() {
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
        db.expect_get_user_by_id().times(0);
        db.expect_user_owns_groups_in_community().times(0);

        // Setup router
        let server_cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            server_cfg: server_cfg.clone(),
            db: db.clone(),
            image_storage: Arc::new(MockImageStorage::new()),
            meetings_cfg: None,
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs_config(),
        };
        let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route(
                "/community/{community_id}/select",
                get(|| async { StatusCode::OK }),
            )
            .layer(middleware::from_fn_with_state(
                state.clone(),
                user_owns_groups_in_path_community,
            ))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri(format!("/community/{community_id}/select"))
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
    async fn test_user_owns_path_community_forbidden_when_not_logged_in() {
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
        db.expect_get_user_by_id().times(0);
        db.expect_user_owns_community().times(0);

        // Setup router
        let server_cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            server_cfg: server_cfg.clone(),
            db: db.clone(),
            image_storage: Arc::new(MockImageStorage::new()),
            meetings_cfg: None,
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs_config(),
        };
        let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route("/{community_id}/protected", get(|| async { StatusCode::OK }))
            .layer(middleware::from_fn_with_state(
                state.clone(),
                user_owns_path_community,
            ))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri(format!("/{community_id}/protected"))
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
    async fn test_user_owns_path_group_forbidden_when_not_logged_in() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let mut session_record = empty_session_record(session_id);
        session_record
            .data
            .insert(SELECTED_COMMUNITY_ID_KEY.to_string(), json!(community_id));

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id().times(0);
        db.expect_user_owns_group().times(0);

        // Setup router
        let server_cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            server_cfg: server_cfg.clone(),
            db: db.clone(),
            image_storage: Arc::new(MockImageStorage::new()),
            meetings_cfg: None,
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs_config(),
        };
        let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route("/groups/{group_id}", get(|| async { StatusCode::OK }))
            .layer(middleware::from_fn_with_state(
                state.clone(),
                user_owns_path_group,
            ))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri(format!("/groups/{group_id}"))
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
    async fn test_user_owns_selected_community_forbidden_when_not_logged_in() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let mut session_record = empty_session_record(session_id);
        session_record
            .data
            .insert(SELECTED_COMMUNITY_ID_KEY.to_string(), json!(community_id));

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id().times(0);
        db.expect_user_owns_community().times(0);

        // Setup router
        let server_cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            server_cfg: server_cfg.clone(),
            db: db.clone(),
            image_storage: Arc::new(MockImageStorage::new()),
            meetings_cfg: None,
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs_config(),
        };
        let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route("/protected", get(|| async { StatusCode::OK }))
            .layer(middleware::from_fn_with_state(
                state.clone(),
                user_owns_selected_community,
            ))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri("/protected")
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
    async fn test_user_owns_selected_group_forbidden_when_not_logged_in() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let mut session_record = empty_session_record(session_id);
        session_record
            .data
            .insert(SELECTED_COMMUNITY_ID_KEY.to_string(), json!(community_id));
        session_record
            .data
            .insert(SELECTED_GROUP_ID_KEY.to_string(), json!(group_id));

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_session()
            .times(1)
            .withf(move |id| *id == session_id)
            .returning(move |_| Ok(Some(session_record.clone())));
        db.expect_get_user_by_id().times(0);
        db.expect_user_owns_group().times(0);

        // Setup router
        let server_cfg = HttpServerConfig::default();
        let db = Arc::new(db);
        let nm = Arc::new(MockNotificationsManager::new());
        let state = State {
            server_cfg: server_cfg.clone(),
            db: db.clone(),
            image_storage: Arc::new(MockImageStorage::new()),
            meetings_cfg: None,
            notifications_manager: nm.clone(),
            serde_qs_de: serde_qs_config(),
        };
        let auth_layer = crate::auth::setup_layer(&server_cfg, db.clone()).await.unwrap();
        let router = Router::new()
            .route("/protected", get(|| async { StatusCode::OK }))
            .layer(middleware::from_fn_with_state(
                state.clone(),
                user_owns_selected_group,
            ))
            .layer(auth_layer)
            .with_state(state);

        // Execute request
        let request = Request::builder()
            .method("GET")
            .uri("/protected")
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

    // Helpers.

    struct MockCallbackAuth {
        login_called: bool,
        login_result: Option<Result<(), HandlerError>>,
        oidc_result: Option<Result<Option<auth::User>, String>>,
        oauth2_result: Option<Result<Option<auth::User>, String>>,
    }

    #[async_trait]
    impl CallbackAuth for MockCallbackAuth {
        async fn authenticate_oauth2(
            &mut self,
            _code: String,
            _provider: OAuth2Provider,
        ) -> Result<Option<auth::User>, String> {
            self.oauth2_result
                .take()
                .expect("oauth2 callback auth result should be configured in tests")
        }

        async fn authenticate_oidc(
            &mut self,
            _code: String,
            _nonce: oidc::Nonce,
            _provider: OidcProvider,
        ) -> Result<Option<auth::User>, String> {
            self.oidc_result
                .take()
                .expect("oidc callback auth result should be configured in tests")
        }

        async fn log_in(&mut self, _user: &auth::User) -> Result<(), HandlerError> {
            self.login_called = true;
            self.login_result
                .take()
                .expect("callback login result should be configured in tests")
        }
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
