<!-- markdownlint-disable MD013 -->

# Badges Guide

OCG badges let groups recognize event attendees, speakers, hosts, and group team members with
portable Open Badges 3.0 credentials.

!> Badges are an experimental feature. Their behavior and interfaces may change as the feature
evolves.

Every award stores an immutable snapshot of the badge and issuing group. The credential therefore
keeps the name, description, criteria, artwork, and issuer that applied when it was awarded, even
if the badge definition, event, group, or recipient account changes later.

**Sections:**

- [Group Badge Management](#group-badge-management)
- [User Badge Operations](#user-badge-operations)

## Group Badge Management

Use this section when your group wants to create badges, award them, or manage award history.

### Access and Badge Setup

Open [Group Dashboard -> Badges](/dashboard/group?tab=badges ':ignore'). Badge management and
awarding require events write access. Group Admins and Events Managers have this permission;
community Admins and Groups Managers inherit it for their groups. Viewers do not see or open the
protected badge-management area.

The badge dashboard has three sections:

- `Badges` creates and edits definitions. Each definition has a name, description, achievement
  criteria, and one gallery image.
- `Awards` searches credential history by recipient or badge and filters by status, definition,
  source event, and award date. Revoked awards remain visible to authorized managers.
- `Artwork` uploads reusable PNG, JPEG, or WebP images. Artwork must be exactly 512 by 512 pixels.

Badge names support up to 200 characters. Descriptions and achievement criteria support up to
10,000 characters each.

Upload artwork before creating a definition. A gallery item cannot be removed while a current
definition references it. Removing a gallery entry never removes an image retained by an issued
credential snapshot.

Deleting a definition does not revoke earlier awards. Those credentials continue to use their
snapshotted name, description, criteria, image, and issuer.

### Award Badges

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

The event's Hosts & Speakers tab offers equivalent actions for contributors:

- A host or event-level speaker row can award a badge to that contributor.
- A session-level speaker row can award a badge to that speaker. Session assignments are still
  edited from the Sessions tab.
- `Award badge to all hosts` awards every current host.
- `Award badge to all speakers` combines and deduplicates event-level and session-level speakers.

Contributor award actions are disabled after an unsaved host, speaker, or session change. Save the
event before awarding so eligibility matches the stored event. New-event forms do not offer award
actions until the event exists.

Accepted members on the Group Team page also have `Award badge` in their row menu when the current
administrator has events write access. Team awards belong to the group and do not need an event.
Pending team invitations are not eligible.

For an event award, every recipient must currently be a confirmed attendee, event host,
event-level speaker, or session-level speaker. An event organizer qualifies only when they also
hold one of those roles. For an award without an event, every recipient must be an accepted member
of that group's team. Canceled events cannot issue awards.

OCG validates the complete recipient list before awarding the badge. If any recipient is
ineligible, nobody in that request receives it. One active award is allowed for each badge and
user. Current holders are skipped, and the result reports both awarded and skipped totals.

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

Open [User Dashboard -> Badges](/dashboard/user?tab=badges ':ignore'). This dashboard shows your
active badges and provides controls for profile listing, order, sharing, export, and revocation.

### Profile Listing and Order

`Show on profile` controls whether a badge appears when someone opens your community-scoped public
profile. Turning it off is reversible and is the right choice when you only want to hide a badge.

!> An unlisted badge is not private. Anyone who already has its direct credential URL can still
open it.

You can reorder badges by dragging them with a pointer or by using `Move up` and `Move down`. Both
controls save the same profile display order.

### Share and Export Credentials

Select `Share` to open the badge's stable public credential page. You can copy that page's URL and
send it directly or add it to a profile, portfolio, or other place where you want to show the
credential. The page displays the badge details, issuing group, award date, and current active or
revoked state.

Select `Export PNG` to download a portable copy. The exported file is a baked Open Badges 3.0
credential: it contains both the badge artwork and the signed credential data.

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

Verification checks the signed credential and reports whether it is active or revoked. An already
exported or shared credential remains available after revocation, but current verification reports
the revoked state.

### Credential Privacy

The portable credential uses an opaque identifier for its subject. It does not contain your email
address, email hash, username, or a stable identifier shared by your other badge awards.

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
