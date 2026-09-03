<!-- markdownlint-disable MD013 -->

# Group Dashboard Guide

Use the Group Dashboard to run your group day to day. This is where organizers
manage events, badges, team coordination, member communication, and sponsors.

If you are still selecting the right workspace, read
[Choose Your Dashboard](../getting-started/choose-dashboard.md).

Path: [/dashboard/group](/dashboard/group ':ignore')

**Sections:**

- [Group Dashboard Guide](#group-dashboard-guide)
  - [What This Dashboard Owns](#what-this-dashboard-owns)
  - [Access and Context](#access-and-context)
  - [Roles and Permissions](#roles-and-permissions)
  - [Settings: Group Identity](#settings-group-identity)
  - [Payments: Fiscal Sponsor Setup](#payments-fiscal-sponsor-setup)
  - [Team: Organizer Capacity](#team-organizer-capacity)
  - [Analytics: Delivery Health](#analytics-delivery-health)
  - [Members: Communication](#members-communication)
  - [Sponsors: Reusable Profiles](#sponsors-reusable-profiles)
  - [Events: Operations Hub](#events-operations-hub)
  - [Badges: Portable Recognition](#badges-portable-recognition)
  - [Refunds: Operational Queue](#refunds-operational-queue)
  - [Audit: Logs](#audit-logs)

## What This Dashboard Owns

The community dashboard sets shared structure. The group dashboard is where you
run the group.

Main areas:

- [Settings](/dashboard/group?tab=settings ':ignore'): group identity and public profile quality.
- [Team](/dashboard/group?tab=team ':ignore'): organizer membership and roles.
- [Analytics](/dashboard/group?tab=analytics ':ignore'): group-level growth trends.
- [Events](/dashboard/group?tab=events ':ignore'): full event lifecycle operations.
- [Check-In](/dashboard/group?tab=check-in ':ignore'): continuous attendee QR scanning and manual
  check-in fallback.
- `Badges`: a main-menu section below `Events` with full-width
  [Badges](/dashboard/group?tab=badges ':ignore'),
  [Artwork](/dashboard/group?tab=artwork ':ignore'), and
  [Awards](/dashboard/group?tab=awards ':ignore') tabs.
- [Refunds](/dashboard/group?tab=refunds ':ignore'): refund review, processing, and recovery work
  for groups with payments set up.
- [Members](/dashboard/group?tab=members ':ignore'): membership view and group-wide communication.
- [Sponsors](/dashboard/group?tab=sponsors ':ignore'): reusable sponsor records for event use.
- [Logs](/dashboard/group?tab=logs ':ignore'): read-only audit trail for group dashboard actions.

## Access and Context

To operate here, you need a logged-in session, group-team membership, and a selected community
and group. If the right community or group is not selected yet, some actions stay unavailable
until you pick them.

## Roles and Permissions

Group role permissions are fixed:

| Group role         | Group read | Check-in  | Events    | Members   | Settings  | Sponsors  | Team      |
| ------------------ | ---------- | --------- | --------- | --------- | --------- | --------- | --------- |
| `admin`            | Yes        | Write     | Write     | Write     | Write     | Write     | Write     |
| `check-in-manager` | Yes        | Write     | Read only | Read only | Read only | Read only | Read only |
| `events-manager`   | Yes        | Write     | Write     | Read only | Read only | Read only | Read only |
| `viewer`           | Yes        | Read only | Read only | Read only | Read only | Read only | Read only |

![Group roles](../screenshots/dashboard-group-members-list-roles.png)

Community roles interact with this dashboard too. Community `admin` and `groups-manager` also
have group write permissions inside that community, while community `viewer` remains read-only at
group scope. In addition, communities can restrict group team management so that only the
community `admin` and `groups-manager` roles can add, update, or remove group team members.

Controls are disabled in the UI when your role does not allow an action, and OCG enforces the
same permissions on every operation.

![Community disabled form](../screenshots/dashboard-group-permissions-role.png)

## Settings: Group Identity

Use `Settings` to maintain the information people rely on before joining or attending.

You can manage:

- Name, category, and descriptions.
- Branding assets.
- Location search and map coordinates.
- Optional pretty URL slug for public group links.
- Social links.
- Optional tags, photo gallery, and extra links.

Enter social and additional links as absolute HTTP or HTTPS URLs. Other URL
schemes and protocol-relative URLs are rejected.

Category and region options in this form come from the defined community's
[Group Categories](/dashboard/community?tab=group-categories ':ignore') and
[Regions](/dashboard/community?tab=regions ':ignore') tabs.

Brand inheritance works as follows in this scope: if a group logo is not set, OCG falls back to
the community logo; if a group banner or mobile banner is not set, OCG falls back to the
community banner; and if a group Open Graph image is not set, group and event link previews fall
back to the community Open Graph image.

Pretty URL slugs are optional. When set, OCG uses the pretty slug in generated
group and event links, while the generated group slug continues to work.

Pretty URL slugs follow these rules:

- Use lowercase ASCII letters, numbers, and hyphens only.
- Start and end with a letter or number.
- Do not use consecutive hyphens.
- Use 50 characters or fewer.
- Use a value that is unique within the community and different from the
  generated slug.

Field requirements and limits are shown inline in the settings form while editing.

### Parent Groups and Subgroups

The `Parent group` section in `Settings` creates a single-level relationship between groups.
Use it when one group should appear under another group on the public site.

The relationship follows these rules:

- A parent must be active, in the same community, and not deleted.
- A parent cannot be a subgroup itself.
- A subgroup cannot have its own subgroups.
- A group with any non-deleted child link cannot be assigned a parent. The selector is disabled
  while those child links exist.
- Choosing a new parent requires settings write access on both this group and the selected parent.
- Clearing the parent only requires settings write access on this group.
- Saving other settings with an unchanged current parent is allowed, even if that parent later
  becomes inactive.

Inactive parents and inactive children are hidden from public relationship displays and merged
event lists, but the stored link is preserved so reactivation is reversible. Deleting a group clears
the parent/child links connected to that group.

![Group settings area](../screenshots/dashboard-group-settings.png)

## Payments: Fiscal Sponsor Setup

Every event uses ticket inventory. Payment setup is unnecessary when every
configured ticket price is zero. Positive pricing requires either server-side Stripe configuration
and a fiscal-sponsor connected account in `Settings`, or the
[external payments](#external-payments) opt-in described below.

To set up the group side, open [Settings](/dashboard/group?tab=settings ':ignore'), enter the
fiscal sponsor's legal name and Stripe connected account ID in the payments section, and save the
group settings. The legal name is shown to attendees as the seller on purchase and refund records.

OCG expects a Stripe connected account identifier in the `acct_...` format.
The dashboard does not create or onboard the Stripe account for you.
The fiscal sponsor owns Tax Rate definitions in that Stripe account. Event
organizers select compatible rates per event in the `Tickets` tab; group
settings do not copy or manage the definitions.

For the full Stripe-side setup, including connected-account onboarding and
payout details, follow [Payments Setup](payments-setup.md).

If the group leaves both fiscal sponsor fields blank, organizers can run events with
free ticket types. A ticket type with any positive current or future price
window makes the event paid-capable and requires the sponsor plus eligible
in-person or hybrid event, complete physical venue, and tax setup. Every paid
hybrid ticket includes physical admission; it may also include virtual access,
but cannot be virtual-only.

If the deployment has no payment provider, the event editor still shows the
`Tickets` tab for free configuration. Positive prices remain unavailable unless
the group has opted into external payments, and group settings do not show a
Stripe fiscal-sponsor field.

Permission-wise, configuring the fiscal sponsor or the external payments toggle requires settings
write access, while creating paid events, marking external payments received, and
approving/rejecting refund requests require events write access.
Organizers with read access can still view attendee refund status in `Event -> Attendees`.

### External payments

Groups in countries that Stripe Connect does not serve can collect ticket
payments outside OCG when the operator has allowlisted the group's country.
When that is the case, `Settings` shows an `External payments` section next to
the fiscal-sponsor section with a `Collect paid tickets outside this platform`
checkbox. Enabling it is an explicit, group-wide opt-in: every paid event in
the group then requires a payment URL instead of Stripe Connect readiness, even
if a fiscal sponsor is also configured.

Rules:

- The group's country, taken from the location field in `Settings`, must be on
  the operator allowlist. When the group has no country or its country is not
  allowlisted, the checkbox is not offered unless it is already on, in which
  case it stays visible so it can be turned off.
- Changing the group country away from an allowlisted country while the
  checkbox stays on is rejected unless the same save turns it off.
- Turning it off is always allowed and stops new external sales immediately.
  Existing pending purchases can still be marked paid, canceled, or refunded.
- Updating or publishing an event that still has an external payment URL is
  rejected while the group is ineligible. Clear the URL to move the event onto
  Stripe only after every pending external purchase has completed, expired, or
  been canceled. Open holds keep using the live event payment URL.
- Group country governs eligibility, not the event venue country.

When the checkbox is on, the event `Tickets` tab asks for:

- A required absolute `http(s)` payment URL.
- Optional payment instructions shown to attendees as plain text.
- An optional payment window in hours; the form shows the operator default and
  maximum. The organizer-confirmation deadline is computed once when a hold is
  created and is the earliest of: hold creation plus the window (capped by the
  operator maximum), the registration close for public checkouts, and the
  event start. Invitation and approval claims are not capped by registration
  close.

Attendees who reserve a ticket receive an email with the payment page link,
their payment reference (the purchase ID), the instructions, and the
confirmation deadline. Holds longer than a day also get one reminder when the
deadline is 24 hours away. When a hold expires or the event is canceled or
unpublished, OCG emails them that the reservation was released and, for
cancellations and unpublishes, not to send payment.

The event `Tickets` tab does not offer a ticket-tax mode for external events:
OCG does not calculate tax, and ticket prices are treated as tax-inclusive.
Organizers remain responsible for tax, receipts, and returning money outside
OCG. Paid events still require in-person or hybrid plus a complete venue.

## Team: Organizer Capacity

`Team` supports invitation-driven organizer management with role updates for existing members.
The assignable roles are `admin`, `check-in-manager`, `events-manager`, and `viewer`.

One important protection applies: the last accepted group admin cannot be removed or demoted.
This protects continuity for critical event operations and approvals.

!> The last accepted group admin cannot be removed or demoted.
Add another accepted team member first, then retry.

When you add a group team member, OCG sends an invitation with a link to
[User Dashboard -> Invitations](/dashboard/user?tab=invitations ':ignore').

Invitation acceptance and dashboard visibility details are covered in
[User Dashboard Guide](user-dashboard.md).

![Group team area](../screenshots/dashboard-user-invitations.png)

## Analytics: Delivery Health

Group analytics focuses on operational output: members, events, attendees, and page views for
the group page and all event pages.

Each metric includes running totals and monthly trends, so it is easier to tell whether growth is
steady over time or mainly tied to isolated spikes.

The `Page views` section starts with total group and event page views, then breaks views down by
page type with daily charts for the last month.

Analytics values can lag briefly due to caching.

When the group has active subgroups, the analytics page shows an `Include subgroups` switch. Turning
it on recalculates every metric on the page across the group and its active subgroups. Member metrics
count unique people across the hierarchy, so someone who belongs to both the parent and a subgroup is
counted once. The switch is not saved; each fresh page load starts with subgroup data excluded.

![Group dashboard analytics](../screenshots/dashboard-group-analytics.png)

## Members: Communication

`Members` provides two practical capabilities: browsing the member list with join dates, and
sending plain-text email to all group members.

`Send email` reaches both group members and group team members who receive optional
notifications. The email form includes a required `Subject`, defaults it to the group name, and
sends the message body as plain text.

![Group members area](../screenshots/dashboard-group-members.png)

## Sponsors: Reusable Profiles

Sponsors are managed once and reused across events, reducing repetitive event setup.
They can also be individually featured on the public group page.
Sponsor website links must be absolute HTTP or HTTPS URLs; other URL schemes
and protocol-relative URLs are rejected.

Typical flow:

1. Create sponsor records in [Sponsors](/dashboard/group?tab=sponsors ':ignore').
2. Mark the sponsors you want highlighted on the public group page.
3. Attach sponsors in event editing (`Hosts & Speakers` section).
4. Update sponsor details once to keep future events consistent.

![Group sponsors area](../screenshots/dashboard-group-sponsors.png)

## Events: Operations Hub

Most organizer time is spent in [Events](/dashboard/group?tab=events ':ignore'): creating drafts,
publishing, managing CFS, reviewing submissions, and running attendance/check-in flows.

The events list keeps an event in `Upcoming events` until its end time passes. When an event has no
end time, its start time is used instead. `Past events` contains events whose applicable time has
already passed.

![Group events area](../screenshots/dashboard-group-events.png)

Starting from [Add Event](/dashboard/group/events/add ':ignore') gives organizers a structured editor with
tabbed sections that map directly to delivery needs. The `Tickets` tab supports
free-only configuration without Stripe, paid configuration when the group is
payment-ready, and a read-only explanation when positive prices cannot be used.
It also contains event currency, ticket-tax mode, inclusive or exclusive tax
display, and the event-wide manual Stripe Tax Rate selector when that mode is
chosen.

Enrollment-aware event operations also include:

- A `Waitlist enabled` toggle in event details.
- New events start with one free, public `General Admission` ticket type with
  500 seats. Organizers can rename it, change its seat count, or add tiers.
- Event capacity is the sum of ticket-type seat counts. It is not edited
  separately, and every event must retain at least one ticket type.
- Waiting lists use each public tier's seat allocation.
- Ticket types can be `Public` or `Invitation only`. Private tiers never appear
  in public event responses.
- Optional `Registration Opens` and `Registration Closes` fields in `Date & Venue`.
  When configured, the window controls public registration, new invitation requests, starting ticket
  checkout, registration-question answers, and automatic waitlist promotion.
  Registration open and close dates cannot be after the event start, and close must be after open
  when both are set. If only an open date is set, registration closes at event start; if both fields
  are blank, no registration window is applied. Organizers can still accept pending invitation
  requests and reissue expired approval offers outside the window until the event is past or
  canceled; rejecting a request and inviting attendees manually still work. Active checkout holds
  may still complete checkout and required registration questions after the public window closes,
  until the hold expires.
- Separate `Attendees`, `Requests`, and `Waitlist` tabs inside the event editor, depending on event
  enrollment settings, with table search, sorting, and filters for day-of operations.
- Automatic reconciliation when attendance, checkout, refund, capacity, or
  offer state releases inventory.
- Waitlist recipients included in event cancellation notifications.

Approval event operations include:

- A `Require Invitation Approval` toggle in event details.
- Approval cannot be combined with waitlist, but it can be used with free or
  paid ticketing.
- Invitation requests appear in a separate `Requests` tab for organizer review. The tab defaults to
  pending requests and can be filtered to all, accepted, or rejected requests. Accept pending
  requests and reissue expired offers while the event is still active, including outside the
  public registration window. `View answers` shows registration answers submitted with a ticket
  request.
- A public ticket request keeps the requester-selected tier.
- A generic request for a fully private event requires the organizer
  to assign an invitation-only tier.
- Accepting a ticket request creates a time-limited offer if capacity and payment
  readiness allow it. The recipient claims the offer through the same checkout
  flow used by public tickets; zero-priced claims complete inside OCG.
- Rejecting a request records the decision without creating an attendee.

Organizer-created event invitations are managed from the event `Attendees` tab:

- Organizers with events write access can invite a registered platform user or enter an email
  address for someone who has not registered yet.
- For new invitees, email invitations should use the invitee's LF account primary email because LF
  SSO activates the placeholder by email. For existing users, select the registered platform user
  when possible; LF SSO identity reconciliation handles later LF email changes during login.
- Invitations require an active, currently priced public or
  invitation-only tier. A zero-priced private tier is the normal complimentary
  option.
- Invitations bypass public approval and registration windows, but never event
  capacity, tier capacity, or public-tier waiting-list priority.
- Pending invitations reserve capacity until their displayed deadline and can
  be canceled before claim. Organizer invitations and approval offers are bounded
  by a 24-hour claim window and event start before the event begins, or event
  end after it starts. Expired organizer invitations may be reissued when the
  recipient is still eligible.
- Declined, canceled, or expired offers release their reservation and trigger
  queue reconciliation. Declined or expired waiting-list recipients are not
  automatically requeued, and their offers cannot be manually reissued.

![Add event flow](../screenshots/dashboard-group-add-event.png)

For complete mechanics, continue to:

- [Event Operations](event-operations.md)

To understand how attendees experience the published result, see
[Public Site Guide](public-site.md).

## Badges: Portable Recognition

`Badges` is where groups create reusable badge definitions, manage artwork, and review active or
revoked award history. Badge management requires badges write access, so Group Admins and Events
Managers can use it while Viewers cannot.

Awards can come from several parts of the group dashboard. Event attendee and contributor actions
recognize confirmed attendees, hosts, and speakers, while accepted group team members can receive
group-level awards from their Team row menu.

For badge setup, eligibility rules, award flows, and revocation, follow the
[Group Badge Management](badges.md#group-badge-management) section of the Badges Guide.

## Refunds: Operational Queue

`Refunds` brings the selected group's attendee requests, automatic refunds, and
related provider processing into one operational view. It includes checkout-only
refunds that may not have a corresponding attendee row, as well as completed and
rejected history.

The tab remains available when the current payment setup is unavailable so
organizers can review historical refunds and recovery records. Restore the
payment provider and fiscal sponsor before retrying provider operations.

Use the views to focus the list:

- `Active` shows all unfinished refund work and is the default.
- `Needs attention` shows requests awaiting review, exhausted retries, and
  provider outcomes that require recovery.
- `Completed` shows refunded purchases and rejected requests.
- `All` shows the complete refund history.

You can search by attendee, event, or ticket and limit the list to one event.
Organizers with events write access can approve or reject pending requests and
retry exhausted non-terminal provider failures from the refund row. They can also queue a full
refund for a confirmed paid attendee by selecting `Cancel attendance and refund` in the event's
`Attendees` tab. Attendance remains active until provider confirmation or recorded manual
recovery, then OCG cancels it and reconciles the released capacity. Read-only
roles can inspect every state but cannot use those actions.

Purchases collected outside OCG through [external payments](#external-payments)
carry an `External` badge in the refunds table. They never involve a payment
provider: approving such a request, or selecting `Cancel attendance and refund`
on the attendee, asks the organizer to confirm that the money was returned
outside OCG, then marks the purchase refunded and cancels the attendance
immediately. Retry and recovery actions do not apply to them.

The `Financial work needs attention` panel appears when automatic attempts for
an application-fee refund, tax fee correction, or credit note are exhausted.
An organizer with events write access can start another bounded retry cycle or
record work completed directly in Stripe. Recording that out-of-band completion
requires the Stripe object ID, a reference for the action taken, and a note
describing the evidence reviewed. OCG stores that evidence and adds the
completion to the audit log.

Rejecting a request requires a reason. The modal identifies it as attendee-visible because the
same reason appears in the attendee's email, `My Events`, and the public event page. Approval notes
remain optional and are kept for organizer review.

When a provider outcome requires recovery, the refund row also offers
`Complete recovery`. Organizers with events write access can use it. Other
roles see the action disabled with an explanation of the requirement. After
arranging the attendee's refund outside OCG, the organizer records the
out-of-band refund reference and the evidence reviewed. OCG then completes any
pending local state, sends the completion notification when needed, and records
the recovery in the audit log.

The event `Attendees` tab shows refund status and the applicable request-review
and retry actions for attendees in that event. Recovery completion is available
only from the group-wide `Refunds` tab. Related application-fee and credit-note
recovery is also available only there. Both views address the underlying
purchase directly, so historical purchases and checkout-only refunds do not
depend on a current attendance row.

## Audit: Logs

`AUDIT -> Logs` is the last section in the left dashboard menu. It provides a read-only record of
group dashboard activity for the selected group.

Coverage in this view includes:

- Group settings updates, including payment recipient and external payments changes.
- Group team changes.
- Sponsor changes.
- Event lifecycle actions such as add, update, publish, unpublish, cancel, and delete.
- Check-ins, CFS submission reviews, and custom notification sends.
- Payment actions such as refund requests, approvals, rejections, recoveries, and external
  payments marked as received.

Rows are ordered by newest first by default, and you can switch the ordering to oldest first. You
can filter by `Action`, `Actor`, and date range, and pagination keeps the active filters applied.
When an audit row has extra metadata, such as a role or notification subject, `Details` opens a
popover with it.

For each entry, OCG shows the resource type plus the current resource name. If the resource no
longer exists, the audit entry still remains and falls back to the stored resource identifier.

This screen is group-dashboard focused, but some overlapping actions, such as `group_updated`,
can also appear in the community dashboard audit view when they match that dashboard's accepted
scope.
