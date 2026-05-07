//! This module defines some handlers used for authentication.

use std::collections::HashMap;

use askama::Template;
use async_trait::async_trait;
use axum::{
    Form,
    extract::{Path, Query, Request, State},
    http::{HeaderMap, StatusCode},
    middleware::Next,
    response::{Html, IntoResponse, Redirect, Response},
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
    types::permissions::{CommunityPermission, GroupPermission},
    validation::{MAX_LEN_S, trimmed_non_empty},
};

#[cfg(test)]
mod tests;

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

/// Ensures the user can enter the community dashboard, falling back to the
/// first accessible community when the selected one is no longer available.
#[instrument(skip_all)]
pub(crate) async fn user_has_community_dashboard_permission(
    State(db): State<DynDB>,
    mut auth_session: AuthSession,
    session: Session,
    request: Request,
    next: Next,
) -> impl IntoResponse {
    // Require an authenticated user
    let Some(user_id) = auth_session.user.as_ref().map(|user| user.user_id) else {
        return StatusCode::FORBIDDEN.into_response();
    };

    // Resolve selected community from session context, repairing it if needed
    let community_id = match get_selected_community_id_optional(&session).await {
        Ok(Some(community_id)) => community_id,
        Ok(None) => match select_first_accessible_community_for_dashboard(&db, &session, &user_id).await {
            Ok(Some(community_id)) => community_id,
            Ok(None) => return Redirect::to(USER_DASHBOARD_INVITATIONS_URL).into_response(),
            Err(error) => return error.into_response(),
        },
        Err(response) => return response,
    };

    // Check base dashboard access in the selected community
    let Ok(has_read_permission) = db
        .user_has_community_permission(&community_id, &user_id, CommunityPermission::Read)
        .await
    else {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    };
    if !has_read_permission {
        return match log_out_for_stale_dashboard_context(&mut auth_session, request.headers()).await {
            Ok(response) => response,
            Err(error) => error.into_response(),
        };
    }

    // Store selected community context for downstream extractors
    let mut request = request;
    request.extensions_mut().insert(SelectedCommunityId(community_id));

    next.run(request).await.into_response()
}

/// Check if the user has a specific community permission in a path community.
#[instrument(skip_all)]
pub(crate) async fn user_has_path_community_permission(
    State((db, permission)): State<(DynDB, CommunityPermission)>,
    Path(community_id): Path<Uuid>,
    auth_session: AuthSession,
    request: Request,
    next: Next,
) -> impl IntoResponse {
    // Require an authenticated user
    let Some(user) = auth_session.user else {
        return StatusCode::FORBIDDEN.into_response();
    };

    // Check required permission against the community id from the path
    let Ok(has_permission) = db
        .user_has_community_permission(&community_id, &user.user_id, permission)
        .await
    else {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    };
    if !has_permission {
        return StatusCode::FORBIDDEN.into_response();
    }

    next.run(request).await.into_response()
}

/// Check if the user has a specific group permission in a path group.
#[instrument(skip_all)]
pub(crate) async fn user_has_path_group_permission(
    State((db, permission)): State<(DynDB, GroupPermission)>,
    Path(group_id): Path<Uuid>,
    auth_session: AuthSession,
    session: Session,
    request: Request,
    next: Next,
) -> impl IntoResponse {
    // Require an authenticated user
    let Some(user) = auth_session.user else {
        return StatusCode::FORBIDDEN.into_response();
    };

    // Resolve selected community to evaluate group permission in that context
    let community_id = match get_selected_community_id(&session).await {
        Ok(community_id) => community_id,
        Err(response) => return response,
    };

    // Check required permission against the group id from the path
    let Ok(has_permission) = db
        .user_has_group_permission(&community_id, &group_id, &user.user_id, permission)
        .await
    else {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    };
    if !has_permission {
        return StatusCode::FORBIDDEN.into_response();
    }

    next.run(request).await.into_response()
}

/// Check if the user has a specific community permission in the selected
/// community.
#[instrument(skip_all)]
pub(crate) async fn user_has_selected_community_permission(
    State((db, permission)): State<(DynDB, CommunityPermission)>,
    mut auth_session: AuthSession,
    session: Session,
    request: Request,
    next: Next,
) -> impl IntoResponse {
    // Require an authenticated user
    let Some(user_id) = auth_session.user.as_ref().map(|user| user.user_id) else {
        return StatusCode::FORBIDDEN.into_response();
    };

    // Resolve selected community from session context, repairing it if needed
    let community_id = match get_selected_community_id_optional(&session).await {
        Ok(Some(community_id)) => community_id,
        Ok(None) => match select_first_accessible_community_for_dashboard(&db, &session, &user_id).await {
            Ok(Some(community_id)) => community_id,
            Ok(None) => return Redirect::to(USER_DASHBOARD_INVITATIONS_URL).into_response(),
            Err(error) => return error.into_response(),
        },
        Err(response) => return response,
    };

    // Check required permission in the selected community
    let Ok(has_permission) = db
        .user_has_community_permission(&community_id, &user_id, permission)
        .await
    else {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    };
    if !has_permission {
        // Missing write permission is a normal 403 when base Read still works
        if permission != CommunityPermission::Read {
            let Ok(has_read_permission) = db
                .user_has_community_permission(&community_id, &user_id, CommunityPermission::Read)
                .await
            else {
                return StatusCode::INTERNAL_SERVER_ERROR.into_response();
            };
            if has_read_permission {
                return StatusCode::FORBIDDEN.into_response();
            }
        }

        // Missing base Read access means the selected community became stale
        return match log_out_for_stale_dashboard_context(&mut auth_session, request.headers()).await {
            Ok(response) => response,
            Err(error) => error.into_response(),
        };
    }

    // Store selected community context for downstream extractors
    let mut request = request;
    request.extensions_mut().insert(SelectedCommunityId(community_id));

    next.run(request).await.into_response()
}

/// Check if the user has a specific group permission in the selected group.
#[instrument(skip_all)]
pub(crate) async fn user_has_selected_group_permission(
    State((db, permission)): State<(DynDB, GroupPermission)>,
    mut auth_session: AuthSession,
    session: Session,
    request: Request,
    next: Next,
) -> impl IntoResponse {
    // Require an authenticated user
    let Some(user_id) = auth_session.user.as_ref().map(|user| user.user_id) else {
        return StatusCode::FORBIDDEN.into_response();
    };

    // Resolve selected community and group from session context, repairing them if needed
    let (community_id, group_id) = match get_selected_community_and_group_ids_optional(&session).await {
        Ok(Some(ids)) => ids,
        Ok(None) => {
            let selected_community_id = match get_selected_community_id_optional(&session).await {
                Ok(selected_community_id) => selected_community_id,
                Err(response) => return response,
            };
            match select_first_accessible_group_for_dashboard(&db, &session, &user_id, selected_community_id)
                .await
            {
                Ok(Some(ids)) => ids,
                Ok(None) => return Redirect::to(USER_DASHBOARD_INVITATIONS_URL).into_response(),
                Err(error) => return error.into_response(),
            }
        }
        Err(response) => return response,
    };

    // Check required permission in the selected group
    let Ok(has_permission) = db
        .user_has_group_permission(&community_id, &group_id, &user_id, permission)
        .await
    else {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    };
    if !has_permission {
        // Missing write permission is a normal 403 when base Read still works
        if permission != GroupPermission::Read {
            let Ok(has_read_permission) = db
                .user_has_group_permission(&community_id, &group_id, &user_id, GroupPermission::Read)
                .await
            else {
                return StatusCode::INTERNAL_SERVER_ERROR.into_response();
            };

            if has_read_permission {
                return StatusCode::FORBIDDEN.into_response();
            }
        }

        // Missing base Read access means the selected group became stale
        return match log_out_for_stale_dashboard_context(&mut auth_session, request.headers()).await {
            Ok(response) => response,
            Err(error) => error.into_response(),
        };
    }

    // Store selected community and group context for downstream extractors
    let mut request = request;
    request.extensions_mut().insert(SelectedCommunityId(community_id));
    request.extensions_mut().insert(SelectedGroupId(group_id));

    next.run(request).await.into_response()
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

/// Resolves the selected community ID from the current session.
async fn get_selected_community_id(session: &Session) -> Result<Uuid, Response> {
    match get_selected_community_id_optional(session).await {
        Ok(Some(community_id)) => Ok(community_id),
        Ok(None) => Err(Redirect::to(USER_DASHBOARD_INVITATIONS_URL).into_response()),
        Err(response) => Err(response),
    }
}

/// Resolves the selected community ID from the current session if present.
async fn get_selected_community_id_optional(session: &Session) -> Result<Option<Uuid>, Response> {
    match session.get::<Uuid>(SELECTED_COMMUNITY_ID_KEY).await {
        Ok(community_id) => Ok(community_id),
        Err(_) => Err(StatusCode::INTERNAL_SERVER_ERROR.into_response()),
    }
}

/// Resolves selected community and group IDs from the current session if present.
async fn get_selected_community_and_group_ids_optional(
    session: &Session,
) -> Result<Option<(Uuid, Uuid)>, Response> {
    // Load selected community context from the session
    let Some(community_id) = get_selected_community_id_optional(session).await? else {
        return Ok(None);
    };

    // Load selected group context from the session
    let group_id = match session.get::<Uuid>(SELECTED_GROUP_ID_KEY).await {
        Ok(Some(group_id)) => group_id,
        Ok(None) => return Ok(None),
        Err(_) => return Err(StatusCode::INTERNAL_SERVER_ERROR.into_response()),
    };

    // Return the complete dashboard context when both parts are present
    Ok(Some((community_id, group_id)))
}

/// Get the sign up url including the next url if provided.
fn get_sign_up_url(next_url: Option<&str>) -> Redirect {
    let mut sign_up_url = SIGN_UP_URL.to_string();
    if let Some(next_url) = sanitize_next_url(next_url) {
        sign_up_url = format!("{sign_up_url}?next_url={}", encode_next_url(&next_url));
    }
    Redirect::to(&sign_up_url)
}

/// Returns whether the request came from HTMX.
fn is_htmx_request(headers: &HeaderMap) -> bool {
    headers
        .get("HX-Request")
        .is_some_and(|value| value.as_bytes().eq_ignore_ascii_case(b"true"))
}

/// Returns whether the request came from an OCG fetch helper.
fn is_ocg_fetch_request(headers: &HeaderMap) -> bool {
    headers
        .get("X-OCG-Fetch")
        .is_some_and(|value| value.as_bytes().eq_ignore_ascii_case(b"true"))
}

/// Logs out the user after detecting a stale dashboard selection.
pub(crate) async fn log_out_for_stale_dashboard_context(
    auth_session: &mut AuthSession,
    headers: &HeaderMap,
) -> Result<Response, HandlerError> {
    auth_session
        .logout()
        .await
        .map_err(|e| HandlerError::Auth(e.to_string()))?;

    Ok(redirect_to_log_in_for_request(headers))
}

/// Builds the log-in redirect response expected by the request type.
fn redirect_to_log_in_for_request(headers: &HeaderMap) -> Response {
    // HTMX follows redirects from response headers when swapping fragments
    if is_htmx_request(headers) {
        return (StatusCode::OK, [("HX-Redirect", LOG_IN_URL)]).into_response();
    }

    // OCG fetch helpers use redirect metadata for browser navigation
    if is_ocg_fetch_request(headers) {
        return (StatusCode::UNAUTHORIZED, [("X-OCG-Redirect", LOG_IN_URL)]).into_response();
    }

    // Normal page requests can use a standard redirect response
    Redirect::to(LOG_IN_URL).into_response()
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

/// Selects the first community dashboard the user can still access.
async fn select_first_accessible_community_for_dashboard(
    db: &DynDB,
    session: &Session,
    user_id: &Uuid,
) -> Result<Option<Uuid>, HandlerError> {
    // Load all community dashboards available to the user
    let communities = db.list_user_communities(user_id).await?;
    let Some(first_community) = communities.first() else {
        return Ok(None);
    };

    // Persist the repaired community dashboard context in the session
    sync_selected_community_and_group(db, session, user_id, first_community.community_id).await?;

    // Return the selected community for downstream request context
    Ok(Some(first_community.community_id))
}

/// Selects the first group dashboard the user can access.
async fn select_first_accessible_group_for_dashboard(
    db: &DynDB,
    session: &Session,
    user_id: &Uuid,
    selected_community_id: Option<Uuid>,
) -> Result<Option<(Uuid, Uuid)>, HandlerError> {
    // Load all group dashboards available to the user
    let groups_by_community = db.list_user_groups(user_id).await?;

    // Prefer the selected community when it has at least one group
    let selected_community = selected_community_id
        .and_then(|community_id| {
            groups_by_community
                .iter()
                .find(|c| c.community.community_id == community_id)
        })
        .filter(|c| !c.groups.is_empty());

    // Fall back to the first community with available groups
    let first_community = selected_community.or_else(|| {
        groups_by_community
            .iter()
            .find(|community| !community.groups.is_empty())
    });
    let Some(first_community) = first_community else {
        return Ok(None);
    };
    let Some(first_group) = first_community.groups.first() else {
        return Ok(None);
    };

    // Persist the repaired dashboard context in the session
    let community_id = first_community.community.community_id;
    let group_id = first_group.group_id;
    session.insert(SELECTED_COMMUNITY_ID_KEY, community_id).await?;
    session.insert(SELECTED_GROUP_ID_KEY, group_id).await?;

    Ok(Some((community_id, group_id)))
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

/// Syncs the selected community and first available group in the session.
pub(crate) async fn sync_selected_community_and_group(
    db: &DynDB,
    session: &Session,
    user_id: &Uuid,
    community_id: Uuid,
) -> Result<(), HandlerError> {
    // Load the user's groups to keep the selected group in sync
    let groups_by_community = db.list_user_groups(user_id).await?;
    let community_groups = groups_by_community
        .iter()
        .find(|c| c.community.community_id == community_id);

    // Persist the community selection and align the group selection with it
    session.insert(SELECTED_COMMUNITY_ID_KEY, community_id).await?;
    if let Some(first_group_id) = community_groups.and_then(|c| c.groups.first()).map(|g| g.group_id) {
        session.insert(SELECTED_GROUP_ID_KEY, first_group_id).await?;
    } else {
        session.remove::<Uuid>(SELECTED_GROUP_ID_KEY).await?;
    }

    Ok(())
}
