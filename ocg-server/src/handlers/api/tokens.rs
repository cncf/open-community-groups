//! API token management handlers.

use axum::{
    Json,
    extract::{Path, State},
    response::IntoResponse,
};
use axum_login::AuthSession;
use garde::Validate;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{auth::AuthnBackend, handlers::extractors::ValidatedJson, router};

use super::auth::{ApiScope, hash_token};
use super::{
    error::ApiError,
    types::{ApiResponse, EmptyData},
};

pub(crate) async fn list(
    State(state): State<router::State>,
    auth_session: AuthSession<AuthnBackend>,
) -> Result<impl IntoResponse, ApiError> {
    let user = auth_session.user.ok_or_else(ApiError::unauthenticated)?;
    Ok(Json(ApiResponse::data(
        state.db.list_api_tokens(user.user_id).await?,
    )))
}

pub(crate) async fn create(
    State(state): State<router::State>,
    auth_session: AuthSession<AuthnBackend>,
    ValidatedJson(input): ValidatedJson<CreateApiTokenInput>,
) -> Result<impl IntoResponse, ApiError> {
    let user = auth_session.user.ok_or_else(ApiError::unauthenticated)?;
    let token = new_token_secret();
    let token_prefix = token.chars().take(17).collect::<String>();
    let scopes = input.scopes.unwrap_or_else(|| vec![ApiScope::ReadPublic]);
    let record = state
        .db
        .create_api_token(
            user.user_id,
            &hash_token(&token),
            &token_prefix,
            input.name,
            &scopes,
        )
        .await?;

    Ok(Json(ApiResponse::data(CreateApiTokenOutput {
        token,
        record,
    })))
}

pub(crate) async fn revoke(
    State(state): State<router::State>,
    auth_session: AuthSession<AuthnBackend>,
    Path(path): Path<TokenPath>,
) -> Result<impl IntoResponse, ApiError> {
    let user = auth_session.user.ok_or_else(ApiError::unauthenticated)?;
    state.db.revoke_api_token(user.user_id, path.token_id).await?;
    Ok(Json(ApiResponse::data(EmptyData {})))
}

fn new_token_secret() -> String {
    format!(
        "goup_{}{}",
        Uuid::new_v4().simple(),
        Uuid::new_v4().simple()
    )
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub(crate) struct CreateApiTokenInput {
    #[garde(length(max = 120))]
    name: Option<String>,
    #[garde(length(min = 1, max = 16))]
    scopes: Option<Vec<ApiScope>>,
}

#[derive(Debug, Clone, Serialize)]
pub(crate) struct CreateApiTokenOutput {
    token: String,
    record: super::auth::ApiToken,
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct TokenPath {
    token_id: Uuid,
}

#[cfg(test)]
mod tests {
    use garde::Validate;

    use super::{ApiScope, CreateApiTokenInput};

    #[test]
    fn create_token_input_requires_at_least_one_scope_when_scopes_are_present() {
        let input = CreateApiTokenInput {
            name: Some("Integration".to_string()),
            scopes: Some(Vec::new()),
        };

        assert!(input.validate().is_err());
    }

    #[test]
    fn create_token_input_accepts_named_scoped_tokens() {
        let input = CreateApiTokenInput {
            name: Some("Integration".to_string()),
            scopes: Some(vec![ApiScope::ReadPublic]),
        };

        assert!(input.validate().is_ok());
    }
}
