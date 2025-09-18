//! Custom extractors for handlers.

use std::sync::Arc;
#[cfg(not(test))]
use std::time::Duration;

use anyhow::Result;
use axum::{
    extract::{FromRequestParts, Path},
    http::{StatusCode, header::HOST, request::Parts},
};
#[cfg(not(test))]
use cached::proc_macro::cached;
use tower_sessions::Session;
use tracing::{error, instrument};
use uuid::Uuid;

use crate::{
    auth::{AuthSession, OAuth2ProviderDetails, OidcProviderDetails},
    config::{OAuth2Provider, OidcProvider},
    db::DynDB,
    handlers::auth::SELECTED_GROUP_ID_KEY,
    router,
};

/// Extractor that resolves a community ID from the request's Host header.
///
/// This enables multi-tenant functionality where different communities are served based
/// on the domain name. The community ID is cached for 24 hours to reduce database
/// lookups.
pub(crate) struct CommunityId(pub Uuid);

impl FromRequestParts<router::State> for CommunityId {
    type Rejection = (StatusCode, &'static str);

    #[instrument(skip_all, err(Debug))]
    async fn from_request_parts(parts: &mut Parts, state: &router::State) -> Result<Self, Self::Rejection> {
        // Extract host from the request headers
        let Some(host_header) = parts.headers.get(HOST) else {
            return Err((StatusCode::BAD_REQUEST, "missing host header"));
        };
        let host = host_header
            .to_str()
            .unwrap_or_default()
            .split(':')
            .next()
            .unwrap_or_default();

        // Lookup the community id in the database
        let Some(community_id) = lookup_community_id(state.db.clone(), host).await.map_err(|err| {
            error!(?err, "error looking up community id");
            (StatusCode::INTERNAL_SERVER_ERROR, "")
        })?
        else {
            return Err((StatusCode::BAD_REQUEST, "community host not found"));
        };

        Ok(CommunityId(community_id))
    }
}

/// Lookup function for resolving community IDs from hostnames.
///
/// In non-test builds, results are cached for 24 hours (86400 seconds) to minimize
/// database queries. During tests the cache is disabled to avoid cross-test
/// contamination when multiple tests reuse the same host value.
#[cfg_attr(
    not(test),
    cached(
        time = 86400,
        key = "String",
        convert = r#"{ String::from(host) }"#,
        sync_writes = "by_key",
        result = true
    )
)]
#[instrument(skip(db), err)]
async fn lookup_community_id(db: DynDB, host: &str) -> Result<Option<Uuid>> {
    if host.is_empty() {
        return Ok(None);
    }
    db.get_community_id(host).await
}

/// Extractor for `OAuth2` provider details from the authenticated session.
pub(crate) struct OAuth2(pub Arc<OAuth2ProviderDetails>);

impl FromRequestParts<router::State> for OAuth2 {
    type Rejection = (StatusCode, &'static str);

    #[instrument(skip_all, err(Debug))]
    async fn from_request_parts(parts: &mut Parts, state: &router::State) -> Result<Self, Self::Rejection> {
        let Ok(provider) = Path::<OAuth2Provider>::from_request_parts(parts, state).await else {
            return Err((StatusCode::BAD_REQUEST, "missing oauth2 provider"));
        };
        let Ok(auth_session) = AuthSession::from_request_parts(parts, state).await else {
            return Err((StatusCode::BAD_REQUEST, "missing auth session"));
        };
        let Some(provider_details) = auth_session.backend.oauth2_providers.get(&provider) else {
            return Err((StatusCode::BAD_REQUEST, "oauth2 provider not supported"));
        };
        Ok(OAuth2(provider_details.clone()))
    }
}

/// Extractor for `Oidc` provider details from the authenticated session.
pub(crate) struct Oidc(pub Arc<OidcProviderDetails>);

impl FromRequestParts<router::State> for Oidc {
    type Rejection = (StatusCode, &'static str);

    #[instrument(skip_all, err(Debug))]
    async fn from_request_parts(parts: &mut Parts, state: &router::State) -> Result<Self, Self::Rejection> {
        let Ok(provider) = Path::<OidcProvider>::from_request_parts(parts, state).await else {
            return Err((StatusCode::BAD_REQUEST, "missing oidc provider"));
        };
        let Ok(auth_session) = AuthSession::from_request_parts(parts, state).await else {
            return Err((StatusCode::BAD_REQUEST, "missing auth session"));
        };
        let Some(provider_details) = auth_session.backend.oidc_providers.get(&provider) else {
            return Err((StatusCode::BAD_REQUEST, "oidc provider not supported"));
        };
        Ok(Oidc(provider_details.clone()))
    }
}

/// Extractor for the selected group ID from the session.
/// Returns the Uuid if present, or an error if not found in the session.
pub(crate) struct SelectedGroupId(pub Uuid);

impl FromRequestParts<router::State> for SelectedGroupId {
    type Rejection = (StatusCode, &'static str);

    #[instrument(skip_all, err(Debug))]
    async fn from_request_parts(parts: &mut Parts, state: &router::State) -> Result<Self, Self::Rejection> {
        let Ok(session) = Session::from_request_parts(parts, state).await else {
            return Err((StatusCode::UNAUTHORIZED, "user not logged in"));
        };
        let group_id: Option<Uuid> = session.get(SELECTED_GROUP_ID_KEY).await.map_err(|_| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                "error getting selected group from session",
            )
        })?;
        match group_id {
            Some(id) => Ok(SelectedGroupId(id)),
            None => Err((StatusCode::BAD_REQUEST, "missing group id")),
        }
    }
}
