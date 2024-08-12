//! Custom extractors for handlers.

use crate::{db::DynDB, router};
use anyhow::Result;
use axum::{
    async_trait,
    extract::FromRequestParts,
    http::{header::HOST, request::Parts, StatusCode},
};
use cached::proc_macro::cached;

/// Custom extractor to get the community from the host header in the request.
pub(crate) struct Community(pub String);

#[async_trait]
impl FromRequestParts<router::State> for Community {
    type Rejection = (StatusCode, &'static str);

    async fn from_request_parts(
        parts: &mut Parts,
        state: &router::State,
    ) -> Result<Self, Self::Rejection> {
        let Some(host_header) = parts.headers.get(HOST) else {
            return Err((StatusCode::BAD_REQUEST, "missing host header"));
        };

        let host = host_header
            .to_str()
            .unwrap_or_default()
            .split(':')
            .next()
            .unwrap_or_default();
        let Some(community) = lookup_community(state.db.clone(), host)
            .map_err(|_| (StatusCode::INTERNAL_SERVER_ERROR, ""))?
        else {
            return Err((StatusCode::BAD_REQUEST, "community host not found"));
        };

        Ok(Community(community))
    }
}

/// Lookup the community in the database using the host provided.
#[cached(
    time = 86400,
    key = "String",
    convert = r#"{ String::from(_host) }"#,
    sync_writes = true,
    result = true
)]
fn lookup_community(_db: DynDB, _host: &str) -> Result<Option<String>> {
    // TODO(tegioz): query database to get the community
    Ok(Some("cncf".to_string()))
}
