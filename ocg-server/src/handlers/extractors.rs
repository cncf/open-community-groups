//! Custom extractors for handlers.

use anyhow::Result;
use axum::{
    extract::FromRequestParts,
    http::{StatusCode, header::HOST, request::Parts},
};
use cached::proc_macro::cached;
use tracing::{error, instrument};
use uuid::Uuid;

use crate::{db::DynDB, router};

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

/// Extractor for the selected group ID from the session.
pub(crate) struct SelectedGroupId(pub Uuid);

impl FromRequestParts<router::State> for SelectedGroupId {
    type Rejection = (StatusCode, &'static str);

    #[instrument(skip_all, err(Debug))]
    async fn from_request_parts(_parts: &mut Parts, _state: &router::State) -> Result<Self, Self::Rejection> {
        // TODO
        Ok(SelectedGroupId(Uuid::nil()))
    }
}

/// Cached lookup function for resolving community IDs from hostnames.
///
/// Results are cached for 24 hours (86400 seconds) to minimize database queries. The
/// cache uses the hostname as the key and is synchronized to prevent duplicate lookups.
#[cached(
    time = 86400,
    key = "String",
    convert = r#"{ String::from(host) }"#,
    sync_writes = "by_key",
    result = true
)]
#[instrument(skip(db), err)]
async fn lookup_community_id(db: DynDB, host: &str) -> Result<Option<Uuid>> {
    if host.is_empty() {
        return Ok(None);
    }
    db.get_community_id(host).await
}
