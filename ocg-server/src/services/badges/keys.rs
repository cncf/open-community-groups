//! Badge credential signing keys and allowlisted verification methods.

use std::collections::HashMap;

use iref::{IriBuf, UriBuf};
use ssi_jwk::{JWK, Params};
use ssi_verification_methods::{AnyMethod, Multikey, ed25519_dalek::VerifyingKey};

use crate::config::BadgesConfig;

use super::{BadgeServiceError, Result};

/// Site badge keys with retained public verification material.
#[derive(Clone)]
pub(super) struct KeySet {
    /// Private key used for new proofs.
    signing_key: SigningKey,
    /// Public keys retained for credential and status verification.
    verification_keys: HashMap<String, JWK>,
}

/// Active credential signing key.
#[derive(Clone)]
pub(super) struct SigningKey {
    /// Stable identifier published in the verification method URL.
    pub(super) key_id: String,
    /// Validated Ed25519 private key material.
    pub(super) private_jwk: JWK,
}

impl KeySet {
    /// Build a key set from validated application configuration.
    pub(super) fn new(config: &BadgesConfig) -> Self {
        // Copy active private material and all explicitly retained public keys
        let signing_key = SigningKey {
            key_id: config.signing_key.key_id.clone(),
            private_jwk: config.signing_key.private_jwk.clone(),
        };
        let mut verification_keys = config
            .verification_keys
            .iter()
            .map(|key| (key.key_id.clone(), key.public_jwk.clone()))
            .collect::<HashMap<_, _>>();

        // Publish the active key through the same closed verification allowlist
        verification_keys.insert(
            signing_key.key_id.clone(),
            signing_key.private_jwk.to_public(),
        );

        // Assemble the validated runtime key set
        Self {
            signing_key,

            verification_keys,
        }
    }

    /// Return all retained stable key identifiers.
    pub(super) fn key_ids(&self) -> Vec<&str> {
        let mut key_ids = self.verification_keys.keys().map(String::as_str).collect::<Vec<_>>();
        key_ids.sort_unstable();
        key_ids
    }

    /// Build an Ed25519 Multikey for one allowlisted verification method URL.
    pub(super) fn multikey(&self, base_url: &str, key_id: &str) -> Result<Multikey> {
        // Load the allowlisted public key material
        let jwk = self
            .public_jwk(key_id)
            .ok_or(BadgeServiceError::UnknownVerificationMethod)?;
        let Params::OKP(params) = &jwk.params else {
            return Err(BadgeServiceError::InvalidKey);
        };

        // Validate the public key bytes as an Ed25519 verifying key
        let public_key: [u8; 32] = params
            .public_key
            .0
            .as_slice()
            .try_into()
            .map_err(|_| BadgeServiceError::InvalidKey)?;
        let public_key =
            VerifyingKey::from_bytes(&public_key).map_err(|_| BadgeServiceError::InvalidKey)?;

        // Build stable verification method and controller URLs
        let key_url = key_url(base_url, key_id)?;
        let controller = UriBuf::new(format!("{base_url}/badges").into_bytes())
            .map_err(|_| BadgeServiceError::InvalidUrl)?;

        // Return the multikey method for the closed resolver
        Ok(Multikey::from_public_key(key_url, controller, &public_key))
    }

    /// Return a retained public JWK by stable key identifier.
    pub(super) fn public_jwk(&self, key_id: &str) -> Option<&JWK> {
        self.verification_keys.get(key_id)
    }

    /// Build the closed SSI resolver used for proof verification.
    pub(super) fn resolver(&self, base_url: &str) -> Result<HashMap<IriBuf, AnyMethod>> {
        self.verification_keys
            .keys()
            .map(|key_id| {
                let method = self.multikey(base_url, key_id)?;
                Ok((method.id.clone(), AnyMethod::Multikey(method)))
            })
            .collect()
    }

    /// Returns the active signing key.
    pub(super) fn signing_key(&self) -> &SigningKey {
        &self.signing_key
    }
}

/// Build a stable verification method URL.
pub(super) fn key_url(base_url: &str, key_id: &str) -> Result<IriBuf> {
    IriBuf::new(format!("{base_url}/badges/keys/{key_id}"))
        .map_err(|_| BadgeServiceError::InvalidUrl)
}
