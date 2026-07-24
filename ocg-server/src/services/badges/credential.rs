//! Open Badges 3.0 credential construction and signing.

use std::collections::HashMap;

use chrono::{DateTime, SecondsFormat, Utc};
use serde_json::{Value, json};
use ssi_claims_core::SignatureEnvironment;
use ssi_data_integrity::{
    AnySignatureOptions, AnySuite, CryptographicSuite, DataIntegrityDocument, ProofOptions,
};
use ssi_verification_methods::{AnyMethod, Multikey, SingleSecretSigner};

use crate::types::badges::UserBadge;

use super::{BadgeService, BadgeServiceError, Result, contexts};

/// Inputs used to issue an immutable Open Badges credential.
pub(crate) struct CredentialInput<'a> {
    /// Durable award state and immutable snapshot.
    pub award: &'a UserBadge,
    /// Proof creation time.
    pub created_at: DateTime<Utc>,
}

impl BadgeService {
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

    /// Sign a supported JSON-LD badge document using eddsa-rdfc-2022.
    pub(super) async fn sign_document(
        &self,
        document: Value,
        created_at: DateTime<Utc>,
    ) -> Result<Value> {
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
        .map_err(|_| BadgeServiceError::SigningFailed)?;
        let document: DataIntegrityDocument =
            serde_json::from_value(document).map_err(|_| BadgeServiceError::InvalidCredential)?;
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
            .map_err(|_| BadgeServiceError::SigningFailed)?;

        serde_json::to_value(signed_document).map_err(|_| BadgeServiceError::InvalidCredential)
    }
}

/// Extract a required string from a credential JSON object.
pub(super) fn required_string<'a>(value: &'a Value, pointer: &str) -> Result<&'a str> {
    value
        .pointer(pointer)
        .and_then(Value::as_str)
        .ok_or(BadgeServiceError::InvalidCredential)
}

/// Serialize timestamps consistently for credentials and proofs.
pub(crate) fn rfc3339(value: DateTime<Utc>) -> String {
    value.to_rfc3339_opts(SecondsFormat::Millis, true)
}
