//! OCG badge credential proof and profile verification.

use serde_json::Value;
use ssi_claims_core::VerificationParameters;
use ssi_data_integrity::{AnyDataIntegrity, DataIntegrityDocument};
use uuid::Uuid;

use super::{
    BadgeService, BadgeServiceError, Result, credential::required_string,
    status::STATUS_LIST_ENTRIES,
};

/// Verified portable credential fields bound to local identifiers by handlers.
pub(crate) struct VerifiedCredential {
    /// Immutable badge description.
    pub description: String,
    /// Issuing group identifier.
    pub group_id: Uuid,
    /// Stable issuer URL.
    pub issuer: String,
    /// Immutable badge name.
    pub name: String,
    /// Stable revocation-list identifier.
    pub status_list_id: Uuid,
    /// Credential index in the referenced status list.
    pub status_list_index: i32,
    /// Opaque local award identifier.
    pub user_badge_id: Uuid,
    /// Credential award timestamp.
    pub valid_from: String,
}

impl BadgeService {
    /// Verifies an OCG credential proof and closed local profile.
    pub(crate) async fn verify_credential(&self, credential: &Value) -> Result<VerifiedCredential> {
        // Validate the closed credential profile and privacy contract
        if credential.get("@context")
            != Some(&serde_json::json!([
                super::contexts::VC_CONTEXT_URL,
                super::contexts::OPEN_BADGES_CONTEXT_URL
            ]))
            || credential.get("type")
                != Some(&serde_json::json!([
                    "VerifiableCredential",
                    "OpenBadgeCredential"
                ]))
            || contains_identifier(credential)
        {
            return Err(BadgeServiceError::InvalidCredential);
        }

        // Resolve and bind the opaque credential and subject identifiers
        let credential_id = required_string(credential, "/id")?;
        let user_badge_id = self.parse_credential_url(credential_id)?;
        let subject_id = required_string(credential, "/credentialSubject/id")?;
        if subject_id != format!("urn:uuid:{user_badge_id}") {
            return Err(BadgeServiceError::InvalidCredential);
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
            return Err(BadgeServiceError::InvalidStatusList);
        }
        let status_list_index = status_list_index
            .parse::<i32>()
            .map_err(|_| BadgeServiceError::InvalidStatusList)?;
        let status_list_entries =
            i32::try_from(STATUS_LIST_ENTRIES).map_err(|_| BadgeServiceError::InvalidStatusList)?;
        if !(0..status_list_entries).contains(&status_list_index) {
            return Err(BadgeServiceError::InvalidStatusList);
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

    /// Verifies one Data Integrity proof with the closed context and key resolvers.
    pub(super) async fn verify_document(&self, document: &Value, issuer_url: &str) -> Result<()> {
        // Validate the fixed proof profile before invoking cryptography
        if required_string(document, "/issuer")? != issuer_url
            || required_string(document, "/proof/type")? != "DataIntegrityProof"
            || required_string(document, "/proof/cryptosuite")? != "eddsa-rdfc-2022"
            || required_string(document, "/proof/proofPurpose")? != "assertionMethod"
        {
            return Err(BadgeServiceError::InvalidProof);
        }

        // Resolve the proof key exclusively through the configured allowlist
        let verification_method = required_string(document, "/proof/verificationMethod")?;
        let key_prefix = format!("{}/badges/keys/", self.base_url);
        let key_id = verification_method
            .strip_prefix(&key_prefix)
            .filter(|key_id| !key_id.is_empty() && !key_id.contains('/'))
            .ok_or(BadgeServiceError::UnknownVerificationMethod)?;
        if self.keys.public_jwk(key_id).is_none() {
            return Err(BadgeServiceError::UnknownVerificationMethod);
        }

        // Deserialize the single proof and build the closed verification environment
        let signed: AnyDataIntegrity<DataIntegrityDocument> =
            serde_json::from_value(document.clone())
                .map_err(|_| BadgeServiceError::InvalidCredential)?;
        if signed.proofs.len() != 1 {
            return Err(BadgeServiceError::InvalidProof);
        }
        let resolver = self.keys.resolver(&self.base_url)?;
        let parameters = VerificationParameters::from_resolver(resolver)
            .with_json_ld_loader(super::contexts::loader()?);

        // Verify the proof and normalize library failures
        let verification = signed
            .verify(parameters)
            .await
            .map_err(|_| BadgeServiceError::InvalidProof)?;
        verification.map_err(|_| BadgeServiceError::InvalidProof)
    }
}

/// Returns whether an uploaded credential contains a portable identifier claim.
fn contains_identifier(value: &Value) -> bool {
    match value {
        Value::Array(values) => values.iter().any(contains_identifier),
        Value::Object(object) => {
            object.contains_key("identifier") || object.values().any(contains_identifier)
        }
        _ => false,
    }
}
