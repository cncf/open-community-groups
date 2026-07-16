<!-- markdownlint-disable MD013 -->

# Badges

OCG badges let groups recognize event attendees, speakers, and hosts with portable
Open Badges 3.0 credentials. A badge remains resolvable after its definition, event, or recipient
account changes because every award stores an immutable snapshot.

## Access and Badge Setup

Open [Group Dashboard -> Badges](/dashboard/group?tab=badges ':ignore'). Badge management and
awarding require `group.events.write`. Group Admins and Events Managers have this permission;
community Admins and Groups Managers inherit it for their groups. Viewers do not see or open the
protected badge-management surface.

The badge dashboard has three sections:

- `Badges` creates and edits definitions. Each definition has a name, description, achievement
  criteria, and one gallery image.
- `Awards` searches credential history by recipient or badge and filters by status, definition,
  source event, and award date. Revoked awards remain visible to authorized managers.
- `Artwork` uploads reusable PNG, JPEG, or WebP images. Artwork must be exactly 512 by 512 pixels.

Badge names support up to 200 characters. Descriptions and achievement criteria support up to
10,000 characters each so every accepted definition remains exportable as a baked credential.

Upload artwork before creating a definition. A gallery item cannot be removed while a current
definition references it. Removing a gallery entry never removes an image retained by an issued
credential snapshot.

Deleting a definition does not revoke earlier awards. Those credentials continue to use their
snapshotted name, description, criteria, image, and issuer.

## Award Badges

The attendee page has a dedicated `Award badge` menu with three choices:

- `All attendees` resolves every confirmed attendee with a verified email address and opens the
  badge picker immediately.
- `Checked-in attendees` does the same for confirmed attendees who are checked in.
- `Choose attendees` enables checkboxes in the attendee table. Filters, sorting, and pagination can
  be changed while choosing; selections remain until they are cleared or canceled. `Continue`
  opens the badge picker for exactly those selected attendees.

An attendee row's three-dot menu awards a badge to that individual attendee. The checkbox workflow
does not add a separate "select all matching" operation; the two event-wide choices cover all and
checked-in recipients directly.

The event's Hosts & Speakers tab uses simple tables for hosts and event-level speakers. Their row
menus can award a badge to one contributor or delete that host or event-level speaker. Adding a
speaker from this tab adds them at the event level. A second table lists each session-level speaker
once and shows all of their associated sessions; its row menu can award a badge but session speaker
assignments are still edited from the Sessions tab.

`Award badge to all hosts` awards every current host. `Award badge to all speakers` combines and
deduplicates event-level and session-level speakers. Contributor award actions are disabled after
an unsaved host, speaker, or session change; save the event before awarding so eligibility matches
the stored event. New-event forms use the same tables for editing but do not offer award actions
until the event exists.

Accepted members on the Group Team page also have `Award badge` in their row menu when the current
administrator has event-management permission. Team awards are group-scoped and do not need an
event. Pending team invitations are not eligible. Team deletion and role controls continue to use
the separate team-management permission and retain the last-admin safeguard.

For an event-scoped award, every verified recipient must currently be a confirmed attendee, event
host, event-level speaker, or session-level speaker. An event organizer qualifies only when they
also hold one of those roles. For an award without an event, every verified recipient must be an
accepted member of that group's team. Canceled events cannot issue awards.

Every award entry point passes an explicit recipient list to the same badge picker and mutation.
The server deduplicates the list and validates every recipient atomically; if any recipient is
ineligible, nobody in that request receives the badge. One active award is allowed for each badge
and user. Current holders are skipped and the result reports both awarded and skipped totals. If a
revoked badge is awarded again, OCG creates a new credential URL, opaque subject, and status-list
entry.

Award insertion and the `badge-awarded` email enqueue happen in one database transaction. Newly
awarded users receive the badge image, description, criteria, issuing group, and a link to their
badge dashboard. Existing active holders receive no duplicate email.

## Revocation

Revocation is permanent. It retains the public credential as history and changes its status-list
bit so standards-based verification reports it as revoked.

Authorized group managers can revoke an active award from the `Awards` section. They must record
an internal reason. OCG records the actor and reason in protected history and sends the recipient a
`badge-revoked` email. The reason is not included in the email or public credential.

Recipients can revoke their own active credential from
[User Dashboard -> Badges](/dashboard/user?tab=badges ':ignore'). Self-revocation needs no reason
and sends no email. Deleting a recipient account also revokes active credentials before removing
the internal user association.

## Profile Listing and Order

The user badge dashboard contains active badges only. `Show on profile` controls discovery in the
community-scoped user profile modal. Turning it off is reversible and is the right choice when a
user only wants to hide a badge.

An unlisted badge is not private: anyone who already has its direct credential URL can still open
it. Direct URLs remain public so shared and baked credentials stay resolvable.

Users can reorder badges by dragging with a pointer or with the `Move up` and `Move down` buttons.
Both controls save the same display order.

## Sharing, Export, and Verification

Each award has a stable public page at:

```text
/badges/credentials/{user_badge_id}
```

The browser page shows the immutable badge snapshot, issuing group, award date, and current active
or revoked state. A request accepting `application/vc+ld+json` receives the signed JSON-LD
credential.

`Export PNG` transcodes the 512-pixel artwork to PNG and adds exactly one uncompressed
`openbadgecredential` iTXt chunk containing the signed credential.

Use `/badges/verify` with an OCG credential UUID or URL, or upload an OCG badge PNG. Verification:

1. accepts only local OCG credential, issuer, key, and status-list URL forms;
2. loads only the reviewed vendored JSON-LD contexts;
3. verifies the `eddsa-rdfc-2022` Data Integrity proof against an allowlisted public key;
4. binds the credential UUID, issuer, status-list UUID, and index to the durable local award; and
5. reports the current active or revoked state from that award.

Uploaded credentials cannot trigger arbitrary URL or context requests. A recipient name appears
only when the opaque award UUID still resolves to a current local account association.

## Credential Privacy and Status

The credential subject is `urn:uuid:{user_badge_id}`. It contains no email address, email hash,
salt, username, Open Badges `IdentityObject`, or stable cross-award recipient identifier. OCG keeps
the recipient association internally while the account exists, but an external verifier cannot
match the portable credential to an email address.

Each group has stable revocation-list UUIDs with 131,072 entries. OCG allocates indexes randomly,
sets bits most-significant-bit first, and publishes a gzip plus multibase-base64url encoded list.
Status-list credentials always declare a 600,000 millisecond TTL and are served with a 600-second
public cache lifetime. The server reuses a size-bounded signed representation while the exact
revocation state remains unchanged. Concurrent cache misses are deduplicated, and changed
revocation state bypasses the application cache on the next origin request.

Stable public infrastructure includes:

```text
/badges/issuers/{group_id}
/badges/keys/{key_id}
/badges/status-lists/{badge_status_list_id}
```

These URLs must remain available for as long as issued credentials may be presented.

## Signing and Key Rotation

The server and Helm chart require one active Ed25519 private JWK. Retained public Ed25519 JWKs are
required after key rotation for as long as credentials reference them:

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

Key IDs are stable lowercase URL-safe identifiers. Private material is rendered through the chart
secret and redacted from configuration debug output and errors. The server refuses to start when
the badge configuration or active signing key is missing.

To rotate keys:

1. Move the old active key's public JWK to `verificationKeys` without changing its key ID.
2. Configure a new private JWK and new key ID as `signingKey`.
3. Keep every public key that may be referenced by an issued credential or status list.

Previously issued credential proofs verify with retained public keys. OCG also requires the active
private key to publish the current signed status-list representation. Operators must back up active
private material and key history independently from application data.
