//! Reviewed JSON-LD contexts used by badge credentials.

use std::collections::HashMap;

use ssi_json_ld::ContextLoader;

use super::{BadgesManagerError, Result};

/// Open Badges 3.0.3 context URL.
pub(super) const OPEN_BADGES_CONTEXT_URL: &str =
    "https://purl.imsglobal.org/spec/ob/v3p0/context-3.0.3.json";

/// VC Data Model 2.0 context URL.
pub(super) const VC_CONTEXT_URL: &str = "https://www.w3.org/ns/credentials/v2";

/// Reviewed Open Badges 3.0.3 context content.
const OPEN_BADGES_CONTEXT: &str = include_str!("contexts/open-badges-v3.json");

/// Reviewed VC Data Model 2.0 context content.
const VC_CONTEXT: &str = include_str!("contexts/credentials-v2.json");

/// Build a context loader with no static or network fallback.
pub(super) fn loader() -> Result<ContextLoader> {
    // Register only the reviewed vendored contexts
    let contexts = HashMap::from([
        (
            OPEN_BADGES_CONTEXT_URL.to_string(),
            OPEN_BADGES_CONTEXT.to_string(),
        ),
        (VC_CONTEXT_URL.to_string(), VC_CONTEXT.to_string()),
    ]);

    // Build a closed loader that cannot fetch unreviewed contexts
    ContextLoader::empty()
        .with_context_map_from(contexts)
        .map_err(|_| BadgesManagerError::InvalidContext)
}

#[cfg(test)]
mod tests {
    use sha2::{Digest, Sha256};

    use super::{OPEN_BADGES_CONTEXT, VC_CONTEXT};

    #[test]
    fn test_reviewed_context_digests_match() {
        // Setup independently reviewed context digests
        let contexts = [
            (
                OPEN_BADGES_CONTEXT,
                "3d34f4d4ef1bce691106e63798beb5e7b862ba841423f5ee1e53ab7ddf3bca84",
            ),
            (
                VC_CONTEXT,
                "59955ced6697d61e03f2b2556febe5308ab16842846f5b586d7f1f7adec92734",
            ),
        ];

        // Calculate and compare every vendored context digest
        for (context, expected) in contexts {
            assert_eq!(hex::encode(Sha256::digest(context)), expected);
        }
    }
}
