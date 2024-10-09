//! Custom extractors for handlers.

use crate::{db::DynDB, router};
use anyhow::Result;
use axum::{
    async_trait,
    extract::FromRequestParts,
    http::{header::HOST, request::Parts, StatusCode},
};
use cached::proc_macro::cached;
use uuid::Uuid;

/// Custom extractor to get the community id from the request's host header.
pub(crate) struct CommunityId(pub Uuid);

#[async_trait]
impl FromRequestParts<router::State> for CommunityId {
    type Rejection = (StatusCode, &'static str);

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
        let Some(community_id) = lookup_community_id(state.db.clone(), host)
            .await
            .map_err(|_| (StatusCode::INTERNAL_SERVER_ERROR, ""))?
        else {
            return Err((StatusCode::BAD_REQUEST, "community host not found"));
        };

        Ok(CommunityId(community_id))
    }
}

/// Lookup the community id in the database using the host provided.
#[cached(
    time = 86400,
    key = "String",
    convert = r#"{ String::from(host) }"#,
    sync_writes = true,
    result = true
)]
async fn lookup_community_id(db: DynDB, host: &str) -> Result<Option<Uuid>> {
    if host.is_empty() {
        return Ok(None);
    }
    db.get_community_id(host).await
}
