//! API bearer-token authentication helpers.

use axum::{
    extract::FromRequestParts,
    http::{header::AUTHORIZATION, request::Parts},
};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::{auth::User, handlers::api::error::ApiError, router};

/// Parsed and authenticated API caller.
#[derive(Debug, Clone)]
pub(crate) struct ApiUser {
    /// Authenticated user.
    pub user: User,
    /// Token scopes granted to the caller.
    pub scopes: Vec<ApiScope>,
}

impl ApiUser {
    /// Require a specific API scope.
    pub(crate) fn require_scope(&self, scope: ApiScope) -> Result<(), ApiError> {
        if self.scopes.contains(&scope) || self.scopes.contains(&ApiScope::AdminPlatform) {
            return Ok(());
        }
        Err(ApiError::forbidden())
    }

    /// Current user id.
    pub(crate) fn user_id(&self) -> Uuid {
        self.user.user_id
    }
}

impl FromRequestParts<router::State> for ApiUser {
    type Rejection = ApiError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &router::State,
    ) -> Result<Self, Self::Rejection> {
        let Some(header) = parts.headers.get(AUTHORIZATION) else {
            return Err(ApiError::unauthenticated());
        };
        let header = header.to_str().map_err(|_| ApiError::unauthenticated())?;
        let Some(token) = header.strip_prefix("Bearer ") else {
            return Err(ApiError::unauthenticated());
        };
        let token_hash = hash_token(token);

        state
            .db
            .get_api_token_auth(&token_hash)
            .await?
            .ok_or_else(ApiError::unauthenticated)
    }
}

/// API token scope.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub(crate) enum ApiScope {
    /// Public read endpoints.
    #[serde(rename = "read:public")]
    ReadPublic,
    /// User profile writes.
    #[serde(rename = "write:profile")]
    WriteProfile,
    /// Event actions and writes.
    #[serde(rename = "write:events")]
    WriteEvents,
    /// Job actions and writes.
    #[serde(rename = "write:jobs")]
    WriteJobs,
    /// Alliance scoped admin actions.
    #[serde(rename = "admin:alliance")]
    AdminAlliance,
    /// Platform admin actions.
    #[serde(rename = "admin:platform")]
    AdminPlatform,
}

impl ApiScope {
    /// Scope as persisted text.
    pub(crate) const fn as_str(self) -> &'static str {
        match self {
            Self::ReadPublic => "read:public",
            Self::WriteProfile => "write:profile",
            Self::WriteEvents => "write:events",
            Self::WriteJobs => "write:jobs",
            Self::AdminAlliance => "admin:alliance",
            Self::AdminPlatform => "admin:platform",
        }
    }
}

impl std::str::FromStr for ApiScope {
    type Err = ();

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "read:public" => Ok(Self::ReadPublic),
            "write:profile" => Ok(Self::WriteProfile),
            "write:events" => Ok(Self::WriteEvents),
            "write:jobs" => Ok(Self::WriteJobs),
            "admin:alliance" => Ok(Self::AdminAlliance),
            "admin:platform" => Ok(Self::AdminPlatform),
            _ => Err(()),
        }
    }
}

/// Hash a bearer token for storage and lookup.
pub(crate) fn hash_token(token: &str) -> String {
    hex::encode(Sha256::digest(token.as_bytes()))
}

/// Non-secret token metadata returned by the API.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct ApiToken {
    /// Token identifier.
    pub api_token_id: Uuid,
    /// Token owner.
    pub user_id: Uuid,
    /// Human-readable name.
    pub name: Option<String>,
    /// Non-secret token prefix.
    pub token_prefix: String,
    /// Token scopes.
    pub scopes: Vec<ApiScope>,
    /// Creation timestamp.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: chrono::DateTime<chrono::Utc>,
    /// Last-used timestamp.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub last_used_at: Option<chrono::DateTime<chrono::Utc>>,
    /// Revocation timestamp.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub revoked_at: Option<chrono::DateTime<chrono::Utc>>,
}

#[cfg(test)]
mod tests {
    use std::str::FromStr;

    use super::{ApiScope, hash_token};

    #[test]
    fn hash_token_is_stable_and_not_plaintext() {
        let hash = hash_token("goup_test_token");

        assert_eq!(
            hash,
            "8a097b2bf9772e4086101d9ebb6791be85bb23d639bdc9915174f5bdd97f920c"
        );
        assert_ne!(hash, "goup_test_token");
    }

    #[test]
    fn api_scope_parses_persisted_scope_strings() {
        assert_eq!(
            ApiScope::from_str("admin:alliance").expect("valid scope"),
            ApiScope::AdminAlliance
        );
        assert!(ApiScope::from_str("admin:unknown").is_err());
    }
}
