<!-- markdownlint-disable MD013 -->

# Badges Guide

OCG badges let groups recognize event attendees, speakers, hosts, and group team members with
portable Open Badges 3.0 credentials.

!> Badges are an experimental feature. Their behavior and interfaces may change as the feature
evolves.

**Sections:**

- [Group Badge Management](#group-badge-management)
- [User Badge Operations](#user-badge-operations)

## Group Badge Management

Use this section when your group wants to create badges, award them, or manage award history.

### Access and Badge Setup

The group dashboard's main menu has a `Badges` section below `Events`. Badge management and
awarding require badges write access. Group Admins and Events Managers have this permission;
community Admins and Groups Managers inherit it for their groups. Viewers do not see or open these
protected tabs.

The section has three full-width tabs:

- [Badges](/dashboard/group?tab=badges ':ignore') creates and edits definitions. Each definition
  has a name, description, achievement criteria, and one gallery image.
- [Artwork](/dashboard/group?tab=artwork ':ignore') opens the `Badges Artwork` page for uploading
  reusable PNG, JPEG, or WebP images. Artwork must be exactly 512 by 512 pixels.
- [Awards](/dashboard/group?tab=awards ':ignore') opens the `Badges Awards` page for searching
  credential history by recipient or badge and filtering by status, definition, source, and award
  date. The source filter selects a specific event or the `Group` source, which covers awards made
  without an event. Revoked awards remain visible to authorized managers.

Badge names support up to 200 characters. Descriptions and achievement criteria support up to
10,000 characters each.

Upload artwork before creating a definition. A gallery item cannot be removed while a current
definition references it. Removing a gallery entry never removes an image retained by an issued
credential snapshot.

Deleting a definition does not revoke earlier awards. Those credentials continue to use their
snapshotted name, description, criteria, image, and issuer.

### Award Badges

Badges can be awarded from three places:

- **Attendees**: the event's attendee page awards badges to confirmed attendees.
- **Contributors**: the event's Hosts & Speakers tab awards badges to hosts and speakers.
- **Organizers**: the Group Team page awards badges to accepted team members. These awards are
  not linked to any event.

#### Attendees

The attendee page has a dedicated `Award badge` menu with three choices:

- `All attendees` resolves every confirmed attendee with a verified email address and opens the
  badge picker immediately.
- `Checked-in attendees` does the same for confirmed attendees who are checked in.
- `Choose attendees` enables checkboxes in the attendee table. Filters, sorting, and pagination can
  be changed while choosing; selections remain until they are cleared or canceled. `Continue`
  opens the badge picker for exactly those selected attendees.

An attendee row's three-dot menu awards a badge to that single attendee.

#### Contributors

The event's Hosts & Speakers tab offers equivalent actions for contributors:

- A host or event-level speaker row can award a badge to that contributor.
- A session-level speaker row can award a badge to that speaker. Session assignments are still
  edited from the Sessions tab.
- `Award badge to all hosts` awards every current host.
- `Award badge to all speakers` combines and deduplicates event-level and session-level speakers.

Contributor award actions are disabled after an unsaved host, speaker, or session change. Save the
event before awarding so eligibility matches the stored event. New-event forms do not offer award
actions until the event exists.

#### Organizers

Accepted members on the Group Team page also have `Award badge` in their row menu when the current
administrator has badges write access. Team awards belong to the group and do not need an event.
Pending team invitations are not eligible.

#### Eligibility and Processing

For an event award, every recipient must currently be a confirmed attendee, event host,
event-level speaker, or session-level speaker. An event organizer qualifies only when they also
hold one of those roles. For an award without an event, every recipient must be an accepted member
of that group's team. Canceled events cannot issue awards.

OCG validates the complete recipient list before awarding the badge. If any recipient is
ineligible, nobody in that request receives it. Each user can hold one active award of a badge:
recipients who already hold it are skipped, and the result reports how many awards were queued and
how many recipients were skipped.

After validation, OCG places accepted awards in a durable queue so large recipient sets do not
affect normal platform traffic. Credentials, award history, and emails may take a short time to
appear. Large awards can take several minutes by design; do not submit the same award again while
it is processing.

New recipients receive an email with the badge image, description, criteria, issuing group, and a
link to [User Dashboard -> Badges](/dashboard/user?tab=badges ':ignore'). Existing active holders
do not receive another award or email.

### Award History and Revocation

Authorized group managers can open `Awards` to review active and revoked credentials. Revocation
is permanent: the public credential remains available as history, but verification reports it as
revoked.

Revoking an active award requires an internal reason. OCG records the actor and reason in protected
history and emails the recipient. The reason is not included in the email or public credential.

Revoking a badge does not prevent the group from awarding the same definition to that user later.
A later award creates a new credential URL.

## User Badge Operations

Use this section to manage badges that groups have awarded to you.

Open [User Dashboard -> Badges](/dashboard/user?tab=badges ':ignore'). The tab shows your active
badges and provides controls for profile listing, ordering, credential viewing and sharing, PNG
download, and revocation.

### Profile Listing and Order

`Show on profile` controls whether a badge appears when someone opens your public profile. Listed
badges are shown together, regardless of the community whose groups awarded them. Turning it off
is reversible and is the right choice when you only want to hide a badge.

!> An unlisted badge is not private. Anyone who already has its direct credential URL can still
open it.

Each badge has a drag handle. You can reorder badges by dragging the handle with a pointer, or by
focusing the handle and pressing `Arrow Up` or `Arrow Down`. Both controls save the same profile
display order.

### Share and Export Credentials

Select `View credential` to open the badge's stable public credential page. You can copy the page
URL and share it directly, or add it to a profile, portfolio, or anywhere else you want to show the
credential. The page displays the badge details, issuing group, award date, and current active or
revoked state.

Select `Download PNG` to download a portable copy. OCG first explains what the file contains and
asks for confirmation before the download starts. The exported file is a baked Open Badges 3.0
credential: it contains both the badge artwork and the signed credential data.

The exported credential identifies you as its recipient through a salted SHA-256 hash of your
account email address, using the Open Badges hashed `IdentityObject` format. Credential platforms
that already know your email address can confirm the badge belongs to you, but the file itself
never contains the email address in plain text. Every download uses a fresh random salt and your
current account email: if your account email changes, download the PNG again to get a credential
bound to the new address.

To move the credential into another compatible system, use that system's badge or credential
import flow. Depending on the system, you can:

- Upload the exported PNG to an Open Badges 3.0-compatible wallet, backpack, or credential
  platform.
- Provide the public credential URL when the system supports importing credentials by URL.

Compatible software can also request `application/vc+ld+json` from the public credential URL to
receive the signed JSON-LD credential directly.

### Verify a Credential

Open [/badges/verify](/badges/verify ':ignore') to verify an OCG credential. You can enter its
public URL or credential ID, or upload an exported PNG.

Verification checks the signed credential and displays its badge artwork, award date, details, and
current active or revoked state. Credentials that were exported or shared before revocation remain
available, but verification reports their revoked state.

You are not limited to OCG's own verifier. Because exported files are standard Open Badges 3.0
credentials, anyone can independently verify them with third-party tools such as
[vc.1ed.tech](https://vc.1ed.tech/) by uploading the exported PNG there.

### Credential Privacy

The public credential page and its signed JSON-LD representation use an opaque identifier for the
subject. They do not contain your email address, email hash, username, or a stable identifier
shared by your other badge awards.

The exported PNG additionally carries a salted SHA-256 hash of your account email so credential
platforms can match the badge to your account. The salt is random for every download, so the email
hash differs between exports and cannot be looked up in precomputed tables. Exports of the same
award still share the credential's stable URL and subject identifier, so two downloads of the same
badge can be recognized as the same credential. A salted hash cannot be reversed into your email
address, but someone who already suspects a specific address can test it against the file, so
share the exported PNG as deliberately as you would any credential file. The file never contains
your email address or username in plain text.

OCG keeps the account association internally while your account exists. The verification page can
show the current recipient name while that internal association remains available.

### Revoke Your Credential

Select `Revoke` from [User Dashboard -> Badges](/dashboard/user?tab=badges ':ignore') to revoke one
of your active credentials. Self-revocation needs no reason and does not send an email.

!> Revocation is permanent. If you only want to remove a badge from your public profile, turn off
`Show on profile` instead.

After revocation, the badge leaves your active badge dashboard and public profile. Its direct page
remains available with a revoked status so previously shared URLs and exported credentials can
still be checked. Deleting your OCG account also revokes its active credentials before removing the
internal account association.
