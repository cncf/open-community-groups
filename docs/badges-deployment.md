<!-- markdownlint-disable MD013 -->

# Badges Deployment Guide

This document is for OCG operators and deployment maintainers. It is intentionally unlisted from
the public docs navigation because it covers credential signing, public verification
infrastructure, and operational requirements.

!> Badges are an experimental feature. Their behavior and interfaces may change as the feature
evolves.

For badge creation, awarding, and recipient workflows, see the
[Badges Guide](guides/badges.md).

## What This Enables

Once badge signing is configured:

- Groups can create badge definitions and award Open Badges 3.0 credentials.
- Recipients can share public credential pages and export baked PNG credentials.
- OCG can publish issuer, verification-key, and status-list documents.
- OCG can verify its own credential URLs, IDs, and exported PNG files.

## OCG Configuration

OCG requires one active Ed25519 private JWK for signing credentials and status lists. The server
refuses to start when the badge configuration or active signing key is missing or invalid.

### Helm Values

The Helm chart exposes badge configuration under `server.badges` in `charts/ocg/values.yaml`:

```yaml
server:
  badges:
    signingKey:
      key_id: active-2026
      private_jwk:
        kty: OKP
        crv: Ed25519
        x: PUBLIC_BASE64URL
        d: PRIVATE_BASE64URL
    verificationKeys:
      - key_id: retired-2025
        public_jwk:
          kty: OKP
          crv: Ed25519
          x: RETIRED_PUBLIC_BASE64URL
```

`signingKey` is required. The chart renders the private key through the server Secret. Keep this
value in a protected values source rather than an ordinary checked-in values file.

`verificationKeys` contains public keys retained from earlier signing-key rotations. It can be
empty on a new deployment, but every retired public key must remain available while issued
credentials still reference it.

### Raw Server Config

If you are not using the Helm chart, the equivalent `server.yml` section is:

```yaml
server:
  badges:
    signing_key:
      key_id: active-2026
      private_jwk:
        kty: OKP
        crv: Ed25519
        x: PUBLIC_BASE64URL
        d: PRIVATE_BASE64URL
    verification_keys:
      - key_id: retired-2025
        public_jwk:
          kty: OKP
          crv: Ed25519
          x: RETIRED_PUBLIC_BASE64URL
```

Key IDs must contain 1 to 64 lowercase URL-safe characters, start and end with a letter or number,
and remain stable after a key is published. Signing keys must contain Ed25519 private material;
retained verification keys must contain public material only.

Private key material is redacted from configuration debug output and errors.

## Public Credential Infrastructure

Badge credentials depend on stable public routes:

```text
/badges/credentials/{user_badge_id}
/badges/issuers/{group_id}
/badges/keys/{key_id}
/badges/status-lists/{badge_status_list_id}
```

These routes use the configured server base URL and must remain publicly available for as long as
issued credentials may be presented. Keep the base URL stable and retain every referenced public
key.

The credential route serves a browser page by default. A request accepting
`application/vc+ld+json` receives the signed JSON-LD credential. The user export route transcodes
the 512-pixel artwork to PNG and adds one uncompressed `openbadgecredential` iTXt chunk containing
a signed credential for the same award.

Each award stores an immutable snapshot of the definition and issuer display data. Deleting or
editing the current definition does not change an issued credential.

## Credential Privacy and Status

The credential subject is `urn:uuid:{user_badge_id}`. It contains no email address, email hash,
salt, username, Open Badges `IdentityObject`, or stable cross-award recipient identifier. OCG keeps
the recipient association internally while the account exists, but an external verifier cannot
derive an email address from the portable credential.

Each group has stable status-list UUIDs with 131,072 entries. OCG allocates indexes randomly, sets
bits most-significant-bit first, and publishes a gzip plus multibase-base64url encoded list.

Status-list credentials declare a 600,000 millisecond TTL and are served with a 600-second public
cache lifetime. The server reuses a size-bounded signed representation while the exact revocation
state remains unchanged. Concurrent cache misses are deduplicated, and changed revocation state
bypasses the application cache on the next origin request.

Revocation is permanent. It retains the credential as public history and changes its status-list
bit so standards-based verification reports it as revoked.

## Verification Safeguards

The verification page is available at `/badges/verify`. It accepts an OCG credential UUID or URL,
or an exported OCG badge PNG.

Verification:

1. accepts only local OCG credential, issuer, key, and status-list URL forms;
2. loads only the reviewed vendored JSON-LD contexts;
3. verifies the `eddsa-rdfc-2022` Data Integrity proof against an allowlisted public key;
4. binds the credential UUID, issuer, status-list UUID, and index to the durable local award; and
5. reports the current active or revoked state from that award.

Uploaded credentials cannot trigger arbitrary URL or context requests. A recipient name appears
only when the opaque award UUID still resolves to a current local account association.

## Signing Key Rotation

To rotate keys:

1. Move the old active key's public JWK to `verificationKeys` without changing its key ID.
2. Configure a new private JWK and new key ID as `signingKey`.
3. Deploy the new configuration together so the old public key remains available when the new key
   becomes active.
4. Keep every public key that may be referenced by an issued credential or status list.

Previously issued credential proofs verify with retained public keys. OCG also requires the active
private key to publish the current signed status-list representation.

Back up active private material and retained key history independently from application data. A
lost active private key prevents the deployment from publishing updated status-list credentials,
and removing a retained public key prevents verification of credentials that reference it.
