//! OCG-owned Open Badges credential, status, key, and PNG manager.

mod award_worker;
mod contexts;
mod credential;
mod keys;
pub(crate) mod png;
mod status;
mod verification;

#[cfg(test)]
mod tests;

use std::collections::HashMap;

use chrono::{DateTime, Utc};
use serde_json::{Value, json};
use ssi_claims_core::{SignatureEnvironment, VerificationParameters};
use ssi_data_integrity::{
    AnyDataIntegrity, AnySignatureOptions, AnySuite, CryptographicSuite, DataIntegrityDocument,
    ProofOptions,
};
use ssi_verification_methods::{AnyMethod, Multikey, SingleSecretSigner};
use thiserror::Error;
use uuid::Uuid;

use crate::{config::BadgesConfig, types::badges::UserBadge};

use credential::required_string;
use status::{STATUS_LIST_ENTRIES, STATUS_LIST_TTL_MS, encode_status_list};
use verification::{VerifiedCredential, contains_identifier};

pub(crate) use award_worker::start_badge_award_workers;
pub(crate) use credential::{CredentialInput, rfc3339};

/// Site-wide badge credential manager.
#[derive(Clone)]
pub(crate) struct BadgesManager {
    /// Canonical public origin without a trailing slash.
    base_url: String,
    /// Signed immutable credential representations.
    credential_cache: credential::CredentialCache,
    /// Active signing and retained verification keys.
    keys: keys::KeySet,
    /// Signed status-list representations bounded by list recency.
    status_list_cache: status::StatusListCache,
}

impl BadgesManager {
    /// Build the manager from application configuration.
    pub(crate) fn new(base_url: &str, config: &BadgesConfig) -> Self {
        Self {
            base_url: base_url.trim_end_matches('/').to_string(),
            credential_cache: credential::CredentialCache::new(),
            keys: keys::KeySet::new(config),
            status_list_cache: status::StatusListCache::new(),
        }
    }

    /// Return a cached signed credential or issue its immutable representation once.
    pub(crate) async fn cached_credential(
        &self,
        award: &UserBadge,
        created_at: DateTime<Utc>,
    ) -> Result<Value> {
        if let Some(credential) = self.credential_cache.get(award.user_badge_id).await {
            return Ok(credential);
        }

        // Bound cold signing concurrency and recheck after any preceding signer finishes
        let _signing_guard = self.credential_cache.signing_guard().await?;
        if let Some(credential) = self.credential_cache.get(award.user_badge_id).await {
            return Ok(credential);
        }

        let credential = self.issue_credential(CredentialInput { award, created_at }).await?;
        self.credential_cache
            .insert(award.user_badge_id, credential.clone())
            .await;

        Ok(credential)
    }

    /// Return a cached signed status list or issue one for changed revocation state.
    pub(crate) async fn cached_status_list(
        &self,
        badge_status_list_id: Uuid,
        group_id: Uuid,
        revoked_indexes: &[i32],
        created_at: DateTime<Utc>,
    ) -> Result<Value> {
        // Reuse only a proof over the exact current group and revocation state
        if let Some(credential) = self
            .status_list_cache
            .get(badge_status_list_id, group_id, revoked_indexes)
            .await
        {
            return Ok(credential);
        }

        // Deduplicate cold misses and recheck after any preceding signer finishes
        let _signing_guard = self.status_list_cache.signing_guard().await;
        if let Some(credential) = self
            .status_list_cache
            .get(badge_status_list_id, group_id, revoked_indexes)
            .await
        {
            return Ok(credential);
        }

        // Sign changed state and make it available to subsequent requests
        let credential = self
            .issue_status_list(badge_status_list_id, group_id, revoked_indexes, created_at)
            .await?;
        self.status_list_cache
            .insert(
                badge_status_list_id,
                credential.clone(),
                group_id,
                revoked_indexes,
            )
            .await;

        Ok(credential)
    }

    /// Return the stable public credential URL.
    pub(crate) fn credential_url(&self, user_badge_id: Uuid) -> String {
        format!("{}/badges/credentials/{user_badge_id}", self.base_url)
    }

    /// Issue and sign one Open Badges 3.0 credential.
    pub(crate) async fn issue_credential(&self, input: CredentialInput<'_>) -> Result<Value> {
        // Resolve stable public identifiers from the immutable award
        let award = input.award;
        let credential_url = self.credential_url(award.user_badge_id);
        let issuer_url = self.issuer_url(award.group_id);
        let status_list_url = self.status_list_url(award.badge_status_list_id);
        let image_url = format!(
            "{}/images/badges/{}",
            self.base_url, award.snapshot.image_file_name
        );

        // Assemble the supported opaque-subject credential profile
        let document = json!({
            "@context": [contexts::VC_CONTEXT_URL, contexts::OPEN_BADGES_CONTEXT_URL],
            "id": credential_url,
            "type": ["VerifiableCredential", "OpenBadgeCredential"],
            "issuer": issuer_url,
            "validFrom": rfc3339(award.awarded_at),
            "name": award.snapshot.name,
            "credentialSubject": {
                "id": format!("urn:uuid:{}", award.user_badge_id),
                "type": ["AchievementSubject"],
                "achievement": {
                    "id": format!("{credential_url}#achievement"),
                    "type": ["Achievement"],
                    "criteria": { "narrative": award.snapshot.criteria },
                    "description": award.snapshot.description,
                    "image": { "id": image_url, "type": "Image" },
                    "name": award.snapshot.name
                }
            },
            "credentialStatus": {
                "id": format!("{credential_url}#status"),
                "type": "BitstringStatusListEntry",
                "statusPurpose": "revocation",
                "statusListIndex": award.status_list_index.to_string(),
                "statusListCredential": status_list_url
            }
        });

        // Sign the complete credential with the active issuer key
        self.sign_document(document, input.created_at).await
    }

    /// Build and sign one revocation-only status-list credential.
    pub(crate) async fn issue_status_list(
        &self,
        badge_status_list_id: Uuid,
        group_id: Uuid,
        revoked_indexes: &[i32],
        created_at: DateTime<Utc>,
    ) -> Result<Value> {
        // Assemble the supported revocation-only status-list profile
        let encoded_list = encode_status_list(revoked_indexes)?;
        let status_list_url = self.status_list_url(badge_status_list_id);
        let issuer_url = self.issuer_url(group_id);
        let document = json!({
            "@context": [contexts::VC_CONTEXT_URL],
            "id": status_list_url,
            "type": ["VerifiableCredential", "BitstringStatusListCredential"],
            "issuer": issuer_url,
            "validFrom": rfc3339(created_at),
            "credentialSubject": {
                "id": format!("{status_list_url}#list"),
                "type": "BitstringStatusList",
                "statusPurpose": "revocation",
                "encodedList": encoded_list,
                "ttl": STATUS_LIST_TTL_MS
            }
        });

        // Sign the complete status-list credential with the active issuer key
        self.sign_document(document, created_at).await
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
        serde_json::to_value(method).map_err(|_| BadgesManagerError::InvalidKey)
    }

    /// Verifies an OCG credential proof and closed local profile.
    pub(crate) async fn verify_credential(&self, credential: &Value) -> Result<VerifiedCredential> {
        // Validate the closed credential profile and privacy contract
        if credential.get("@context")
            != Some(&json!([
                contexts::VC_CONTEXT_URL,
                contexts::OPEN_BADGES_CONTEXT_URL
            ]))
            || credential.get("type")
                != Some(&json!(["VerifiableCredential", "OpenBadgeCredential"]))
            || contains_identifier(credential)
        {
            return Err(BadgesManagerError::InvalidCredential);
        }

        // Resolve and bind the opaque credential and subject identifiers
        let credential_id = required_string(credential, "/id")?;
        let user_badge_id = self.parse_credential_url(credential_id)?;
        let subject_id = required_string(credential, "/credentialSubject/id")?;
        if subject_id != format!("urn:uuid:{user_badge_id}") {
            return Err(BadgesManagerError::InvalidCredential);
        }

        // Verify the issuer identity and credential proof
        let issuer = required_string(credential, "/issuer")?;
        let group_id = self.parse_issuer_url(issuer)?;
        self.verify_document(credential, issuer).await?;

        // Validate the credential's bounded local status-list reference
        let status_url = required_string(credential, "/credentialStatus/statusListCredential")?;
        let status_list_id = self.parse_status_list_url(status_url)?;
        let status_list_index = required_string(credential, "/credentialStatus/statusListIndex")?;
        if status_list_index.is_empty()
            || !status_list_index.bytes().all(|byte| byte.is_ascii_digit())
            || (status_list_index.len() > 1 && status_list_index.starts_with('0'))
            || required_string(credential, "/credentialStatus/type")? != "BitstringStatusListEntry"
            || required_string(credential, "/credentialStatus/id")?
                != format!("{credential_id}#status")
            || required_string(credential, "/credentialStatus/statusPurpose")? != "revocation"
        {
            return Err(BadgesManagerError::InvalidStatusList);
        }
        let status_list_index = status_list_index
            .parse::<i32>()
            .map_err(|_| BadgesManagerError::InvalidStatusList)?;
        let status_list_entries = i32::try_from(STATUS_LIST_ENTRIES)
            .map_err(|_| BadgesManagerError::InvalidStatusList)?;
        if !(0..status_list_entries).contains(&status_list_index) {
            return Err(BadgesManagerError::InvalidStatusList);
        }

        // Return the verified fields needed for local persistence binding
        Ok(VerifiedCredential {
            description: required_string(credential, "/credentialSubject/achievement/description")?
                .to_string(),
            group_id,
            issuer: issuer.to_string(),
            name: required_string(credential, "/credentialSubject/achievement/name")?.to_string(),
            status_list_id,
            status_list_index,
            user_badge_id,
            valid_from: required_string(credential, "/validFrom")?.to_string(),
        })
    }

    /// Parse an exact base-URL-relative endpoint containing one UUID.
    fn parse_local_uuid_url(&self, value: &str, path: &str) -> Result<Uuid> {
        let prefix = format!("{}{path}", self.base_url);
        let id = value
            .strip_prefix(&prefix)
            .filter(|id| !id.contains('/'))
            .ok_or(BadgesManagerError::InvalidUrl)?;
        Uuid::parse_str(id).map_err(|_| BadgesManagerError::InvalidUrl)
    }

    /// Sign a supported JSON-LD badge document using eddsa-rdfc-2022.
    async fn sign_document(&self, document: Value, created_at: DateTime<Utc>) -> Result<Value> {
        // Resolve the active key and its allowlisted verification method
        let signing_key = self.keys.signing_key();
        let method = self.keys.multikey(&self.base_url, &signing_key.key_id)?;
        let method_url = method.id.clone();
        let resolver = HashMap::from([(method_url.clone(), AnyMethod::Multikey(method))]);

        // Build the fixed proof options and closed JSON-LD environment
        let proof_options: ProofOptions<Multikey, ()> = serde_json::from_value(json!({
            "created": rfc3339(created_at),
            "verificationMethod": method_url,
            "proofPurpose": "assertionMethod"
        }))
        .map_err(|_| BadgesManagerError::SigningFailed)?;
        let document: DataIntegrityDocument =
            serde_json::from_value(document).map_err(|_| BadgesManagerError::InvalidCredential)?;
        let environment = SignatureEnvironment {
            json_ld_loader: contexts::loader()?,
            eip712_loader: (),
        };
        let signer = SingleSecretSigner::new(signing_key.private_jwk.clone()).into_local();

        // Sign with the required cryptosuite and serialize the result
        let signed_document = AnySuite::EdDsaRdfc2022
            .sign_with(
                environment,
                document,
                resolver,
                signer,
                proof_options.cast(),
                AnySignatureOptions::default(),
            )
            .await
            .map_err(|_| BadgesManagerError::SigningFailed)?;

        serde_json::to_value(signed_document).map_err(|_| BadgesManagerError::InvalidCredential)
    }

    /// Verifies one Data Integrity proof with the closed context and key resolvers.
    async fn verify_document(&self, document: &Value, issuer_url: &str) -> Result<()> {
        // Validate the fixed proof profile before invoking cryptography
        if required_string(document, "/issuer")? != issuer_url
            || required_string(document, "/proof/type")? != "DataIntegrityProof"
            || required_string(document, "/proof/cryptosuite")? != "eddsa-rdfc-2022"
            || required_string(document, "/proof/proofPurpose")? != "assertionMethod"
        {
            return Err(BadgesManagerError::InvalidProof);
        }

        // Resolve the proof key exclusively through the configured allowlist
        let verification_method = required_string(document, "/proof/verificationMethod")?;
        let key_prefix = format!("{}/badges/keys/", self.base_url);
        let key_id = verification_method
            .strip_prefix(&key_prefix)
            .filter(|key_id| !key_id.is_empty() && !key_id.contains('/'))
            .ok_or(BadgesManagerError::UnknownVerificationMethod)?;
        if self.keys.public_jwk(key_id).is_none() {
            return Err(BadgesManagerError::UnknownVerificationMethod);
        }

        // Deserialize the single proof and build the closed verification environment
        let signed: AnyDataIntegrity<DataIntegrityDocument> =
            serde_json::from_value(document.clone())
                .map_err(|_| BadgesManagerError::InvalidCredential)?;
        if signed.proofs.len() != 1 {
            return Err(BadgesManagerError::InvalidProof);
        }
        let resolver = self.keys.resolver(&self.base_url)?;
        let parameters = VerificationParameters::from_resolver(resolver)
            .with_json_ld_loader(contexts::loader()?);

        // Verify the proof and normalize library failures
        let verification = signed
            .verify(parameters)
            .await
            .map_err(|_| BadgesManagerError::InvalidProof)?;
        verification.map_err(|_| BadgesManagerError::InvalidProof)
    }
}

/// Badges manager failures translated into safe handler-level errors.
#[derive(Debug, Error)]
pub(crate) enum BadgesManagerError {
    /// The bounded credential signer is busy serving another cold request.
    #[error("badge credential signer is busy")]
    Busy,
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
    #[error("invalid badge URL")]
    InvalidUrl,
    /// A configured or uploaded PNG exceeds a supported limit.
    #[error("Open Badges PNG exceeds the supported size limit")]
    PngLimitExceeded,
    /// Signing failed without exposing key or proof internals.
    #[error("badge credential signing failed")]
    SigningFailed,
    /// The proof references a key outside the configured allowlist.
    #[error("unknown badge verification method")]
    UnknownVerificationMethod,
}

/// Shared badges manager result.
pub(crate) type Result<T> = std::result::Result<T, BadgesManagerError>;
