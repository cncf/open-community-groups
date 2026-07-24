//! OCG-owned Open Badges credential, status, key, and PNG service.

mod contexts;
mod credential;
mod keys;
pub(crate) mod png;
mod status;
mod verification;

#[cfg(test)]
mod tests;

use thiserror::Error;
use uuid::Uuid;

use crate::config::BadgesConfig;

pub(crate) use credential::{CredentialInput, rfc3339};

/// Site-wide badge credential service.
#[derive(Clone)]
pub(crate) struct BadgeService {
    /// Canonical public origin without a trailing slash.
    base_url: String,
    /// Active signing and retained verification keys.
    keys: keys::KeySet,
    /// Signed status-list representations bounded by list recency.
    status_list_cache: status::StatusListCache,
}

impl BadgeService {
    /// Build the service from application configuration.
    pub(crate) fn new(base_url: &str, config: &BadgesConfig) -> Self {
        Self {
            base_url: base_url.trim_end_matches('/').to_string(),
            keys: keys::KeySet::new(config),
            status_list_cache: status::StatusListCache::new(),
        }
    }

    /// Return the stable public credential URL.
    pub(crate) fn credential_url(&self, user_badge_id: Uuid) -> String {
        format!("{}/badges/credentials/{user_badge_id}", self.base_url)
    }

    /// Return the stable public issuer profile URL.
    pub(crate) fn issuer_url(&self, group_id: Uuid) -> String {
        format!("{}/badges/issuers/{group_id}", self.base_url)
    }

    /// Parse and allowlist one local credential URL.
    pub(crate) fn parse_credential_url(&self, value: &str) -> Result<Uuid> {
        self.parse_local_uuid_url(value, "/badges/credentials/")
    }

    /// Parse and allowlist one local issuer URL.
    pub(crate) fn parse_issuer_url(&self, value: &str) -> Result<Uuid> {
        self.parse_local_uuid_url(value, "/badges/issuers/")
    }

    /// Parse and allowlist one local status-list URL.
    pub(crate) fn parse_status_list_url(&self, value: &str) -> Result<Uuid> {
        self.parse_local_uuid_url(value, "/badges/status-lists/")
    }

    /// Return the stable public status-list credential URL.
    pub(crate) fn status_list_url(&self, badge_status_list_id: Uuid) -> String {
        format!(
            "{}/badges/status-lists/{badge_status_list_id}",
            self.base_url
        )
    }

    /// Return retained public key identifiers.
    pub(crate) fn verification_key_ids(&self) -> Vec<&str> {
        self.keys.key_ids()
    }

    /// Return a retained public key as a stable Multikey verification method.
    pub(crate) fn verification_method(&self, key_id: &str) -> Result<serde_json::Value> {
        let method = self.keys.multikey(&self.base_url, key_id)?;
        serde_json::to_value(method).map_err(|_| BadgeServiceError::InvalidKey)
    }

    /// Parse an exact base-URL-relative endpoint containing one UUID.
    fn parse_local_uuid_url(&self, value: &str, path: &str) -> Result<Uuid> {
        let prefix = format!("{}{path}", self.base_url);
        let id = value
            .strip_prefix(&prefix)
            .filter(|id| !id.contains('/'))
            .ok_or(BadgeServiceError::InvalidUrl)?;
        Uuid::parse_str(id).map_err(|_| BadgeServiceError::InvalidUrl)
    }
}

/// Badge service failures translated into safe handler-level errors.
#[derive(Debug, Error)]
pub(crate) enum BadgeServiceError {
    /// A reviewed JSON-LD context could not be loaded.
    #[error("invalid badge context configuration")]
    InvalidContext,
    /// The credential is malformed or outside the supported OCG profile.
    #[error("invalid badge credential")]
    InvalidCredential,
    /// The supplied image cannot be exported.
    #[error("invalid badge image")]
    InvalidImage,
    /// Configured key material is invalid.
    #[error("invalid badge key configuration")]
    InvalidKey,
    /// The supplied PNG is malformed or outside the supported profile.
    #[error("invalid Open Badges PNG")]
    InvalidPng,
    /// The credential proof is missing or invalid.
    #[error("badge credential proof verification failed")]
    InvalidProof,
    /// The status-list credential is malformed or unsupported.
    #[error("invalid badge status list")]
    InvalidStatusList,
    /// A configured public URL is invalid.
    #[error("invalid badge service URL")]
    InvalidUrl,
    /// A configured or uploaded PNG exceeds a service limit.
    #[error("Open Badges PNG exceeds the supported size limit")]
    PngLimitExceeded,
    /// Signing failed without exposing key or proof internals.
    #[error("badge credential signing failed")]
    SigningFailed,
    /// The proof references a key outside the configured allowlist.
    #[error("unknown badge verification method")]
    UnknownVerificationMethod,
}

/// Shared badge service result.
pub(crate) type Result<T> = std::result::Result<T, BadgeServiceError>;
