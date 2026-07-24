//! Reviewed JSON-LD contexts used by badge credentials.

use std::collections::HashMap;

use ssi_json_ld::ContextLoader;

use super::{BadgeServiceError, Result};

/// Open Badges 3.0.3 context URL.
pub(super) const OPEN_BADGES_CONTEXT_URL: &str =
    "https://purl.imsglobal.org/spec/ob/v3p0/context-3.0.3.json";
/// VC Data Model 2.0 context URL.
pub(super) const VC_CONTEXT_URL: &str = "https://www.w3.org/ns/credentials/v2";

const OPEN_BADGES_CONTEXT: &str = include_str!("contexts/open-badges-v3.json");
const VC_CONTEXT: &str = include_str!("contexts/credentials-v2.json");

/// Build a context loader with no static or network fallback.
pub(super) fn loader() -> Result<ContextLoader> {
    let contexts = HashMap::from([
        (
            OPEN_BADGES_CONTEXT_URL.to_string(),
            OPEN_BADGES_CONTEXT.to_string(),
        ),
        (VC_CONTEXT_URL.to_string(), VC_CONTEXT.to_string()),
    ]);

    ContextLoader::empty()
        .with_context_map_from(contexts)
        .map_err(|_| BadgeServiceError::InvalidContext)
}

#[cfg(test)]
pub(super) fn reviewed_contexts() -> [(&'static str, &'static [u8]); 2] {
    [
        (OPEN_BADGES_CONTEXT_URL, OPEN_BADGES_CONTEXT.as_bytes()),
        (VC_CONTEXT_URL, VC_CONTEXT.as_bytes()),
    ]
}
