//! Utility functions shared across modules.

use sha2::{Digest, Sha256};

/// Computes the SHA-256 hash of the provided bytes and returns a hex string.
pub(crate) fn compute_hash(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    format!("{:x}", hasher.finalize())
}
