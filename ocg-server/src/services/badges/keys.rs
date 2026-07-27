//! Badge credential signing keys and allowlisted verification methods.

use std::collections::HashMap;

use iref::{IriBuf, UriBuf};
use ssi_jwk::{JWK, Params};
use ssi_verification_methods::{AnyMethod, Multikey, ed25519_dalek::VerifyingKey};

use crate::config::BadgesConfig;

use super::{BadgesManagerError, Result};

/// Site badge keys with retained public verification material.
#[derive(Clone)]
pub(super) struct KeySet {
    /// Private key used for new proofs.
    signing_key: SigningKey,
    /// Public keys retained for credential and status verification.
    verification_keys: HashMap<String, JWK>,
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

    /// Builds an issuer-controlled Ed25519 Multikey for one allowlisted key.
    pub(super) fn multikey(&self, issuer_url: &str, key_id: &str) -> Result<Multikey> {
        // Load the allowlisted public key material
        let jwk = self
            .public_jwk(key_id)
            .ok_or(BadgesManagerError::UnknownVerificationMethod)?;
        let Params::OKP(params) = &jwk.params else {
            return Err(BadgesManagerError::InvalidKey);
        };

        // Validate the public key bytes as an Ed25519 verifying key
        let public_key: [u8; 32] = params
            .public_key
            .0
            .as_slice()
            .try_into()
            .map_err(|_| BadgesManagerError::InvalidKey)?;
        let public_key =
            VerifyingKey::from_bytes(&public_key).map_err(|_| BadgesManagerError::InvalidKey)?;

        // Build the issuer controller and encode the public key as a Multikey
        let controller = UriBuf::new(issuer_url.as_bytes().to_vec())
            .map_err(|_| BadgesManagerError::InvalidUrl)?;
        let placeholder_id =
            IriBuf::new(issuer_url.to_string()).map_err(|_| BadgesManagerError::InvalidUrl)?;
        let mut method = Multikey::from_public_key(placeholder_id, controller, &public_key);

        // Identify the method with its dereferenceable public-key URL
        method.id = IriBuf::new(format!(
            "{issuer_url}/keys/{}",
            method.public_key.encoded.as_str()
        ))
        .map_err(|_| BadgesManagerError::InvalidUrl)?;

        Ok(method)
    }

    /// Looks up one retained issuer-controlled Multikey by its multibase value.
    pub(super) fn multikey_by_multibase(
        &self,
        issuer_url: &str,
        key_multibase: &str,
    ) -> Result<Multikey> {
        // Match the requested public key against the retained allowlist
        self.multikeys(issuer_url)?
            .into_iter()
            .find(|method| method.public_key.encoded.as_str() == key_multibase)
            .ok_or(BadgesManagerError::UnknownVerificationMethod)
    }

    /// Builds every retained issuer-controlled Multikey in stable key order.
    pub(super) fn multikeys(&self, issuer_url: &str) -> Result<Vec<Multikey>> {
        // Sort internal identifiers to keep the public controller document deterministic
        let mut key_ids = self.verification_keys.keys().map(String::as_str).collect::<Vec<_>>();
        key_ids.sort_unstable();

        // Derive one self-contained verification method per retained public key
        key_ids
            .into_iter()
            .map(|key_id| self.multikey(issuer_url, key_id))
            .collect()
    }

    /// Build the closed SSI resolver used for proof verification.
    pub(super) fn resolver(&self, issuer_url: &str) -> Result<HashMap<IriBuf, AnyMethod>> {
        Ok(self
            .multikeys(issuer_url)?
            .into_iter()
            .map(|method| (method.id.clone(), AnyMethod::Multikey(method)))
            .collect())
    }

    /// Returns the active signing key.
    pub(super) fn signing_key(&self) -> &SigningKey {
        &self.signing_key
    }

    /// Returns a retained public JWK by its internal stable identifier.
    fn public_jwk(&self, key_id: &str) -> Option<&JWK> {
        self.verification_keys.get(key_id)
    }
}

/// Active credential signing key.
#[derive(Clone)]
pub(super) struct SigningKey {
    /// Stable internal identifier used to select configured key material.
    pub(super) key_id: String,
    /// Validated Ed25519 private key material.
    pub(super) private_jwk: JWK,
}
