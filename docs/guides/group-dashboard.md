<!-- markdownlint-disable MD013 -->

# Group Dashboard Guide

Use the Group Dashboard to run your group day to day. This is where organizers
manage events, team coordination, member communication, and sponsors.

If you are still selecting the right workspace, read
[Choose Your Dashboard](../getting-started/choose-dashboard.md).

Path: [/dashboard/group](/dashboard/group ':ignore')

**Sections:**

- [Group Dashboard Guide](#group-dashboard-guide)
  - [What This Dashboard Owns](#what-this-dashboard-owns)
  - [Access and Context](#access-and-context)
  - [Roles and Permissions](#roles-and-permissions)
  - [Settings: Group Identity](#settings-group-identity)
  - [Payments: Group Recipient Setup](#payments-group-recipient-setup)
  - [Team: Organizer Capacity](#team-organizer-capacity)
  - [Analytics: Delivery Health](#analytics-delivery-health)
  - [Members: Communication](#members-communication)
  - [Sponsors: Reusable Profiles](#sponsors-reusable-profiles)
  - [Events: Operations Hub](#events-operations-hub)
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
- [Refunds](/dashboard/group?tab=refunds ':ignore'): refund review, processing, and recovery work.
- [Members](/dashboard/group?tab=members ':ignore'): membership view and group-wide communication.
- [Sponsors](/dashboard/group?tab=sponsors ':ignore'): reusable sponsor records for event use.
- [Logs](/dashboard/group?tab=logs ':ignore'): read-only audit trail for group dashboard actions.

## Access and Context

To operate here, you need a logged-in session, group-team membership, and a selected community
and group. If the right community or group is not selected yet, some actions stay unavailable
until you pick them.

## Roles and Permissions

Group role permissions are fixed:

| Group role       | Group read | Events    | Members   | Settings  | Sponsors  | Team      |
| ---------------- | ---------- | --------- | --------- | --------- | --------- | --------- |
| `admin`          | Yes        | Write     | Write     | Write     | Write     | Write     |
| `events-manager` | Yes        | Write     | Read only | Read only | Read only | Read only |
| `viewer`         | Yes        | Read only | Read only | Read only | Read only | Read only |

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

## Payments: Group Recipient Setup

Ticketed events are available only when two prerequisites are both true: your OCG deployment has
payments enabled, and the group has a payment recipient configured in `Settings`.

To set up the group side, open [Settings](/dashboard/group?tab=settings ':ignore'), enter the
group's Stripe connected account ID in the payments section, and save the group settings.

OCG expects a Stripe connected account identifier in the `acct_...` format.
The dashboard does not create or onboard the Stripe account for you.

For the full Stripe-side setup, including connected-account onboarding and
payout details, follow [Payments Setup](payments-setup.md).

If the group leaves the payment recipient blank, organizers can still run free
RSVP events, but ticketed events stay unavailable for that group, including
zero-price tiers.

If you do not see payment controls in the event editor at all, your deployment may not have
payments enabled yet. That setup is managed outside the public dashboard documentation.

Permission-wise, configuring the group payment recipient requires settings write access, while
creating paid events and approving/rejecting refund requests require events write access.
Organizers with read access can still view attendee refund status in `Event -> Attendees`.

## Team: Organizer Capacity

`Team` supports invitation-driven organizer management with role updates for existing members.
The assignable roles are `admin`, `events-manager`, and `viewer`.

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
tabbed sections that map directly to delivery needs (details, schedule, roles, sessions, CFS,
attendees).

Waitlist-aware event operations also include:

- A `Waitlist enabled` toggle in event details.
- Waitlist requires a numeric event capacity; unlimited-capacity events cannot enable it.
- Optional `Registration Opens` and `Registration Closes` fields in `Date & Venue`.
  When configured, the window controls public registration, invitation requests, starting ticket
  checkout, registration-question answers, and automatic waitlist promotion.
  Registration open and close dates cannot be after the event start, and close must be after open
  when both are set. If only an open date is set, registration closes at event start; if both fields
  are blank, no registration window is applied. Active checkout holds may still complete payment and
  required registration questions after the public window closes, until the hold expires.
- Separate `Attendees`, `Requests`, and `Waitlist` tabs inside the event editor, depending on event
  enrollment settings, with table search, sorting, and filters for day-of operations.
- Automatic promotion from the waitlist when attendees leave, capacity increases, or capacity is
  removed, but only while registration is open.
- Waitlist recipients included in event cancellation notifications.

Invitation-review event operations include:

- A `Require Invitation Approval` toggle in event details.
- Invitation review cannot be combined with waitlist or paid tickets.
- Invitation requests appear in a separate `Requests` tab for organizer review. The tab defaults to
  pending requests and can be filtered to all, accepted, or rejected requests.
- Accepting a request creates a confirmed attendee if capacity allows.
- Rejecting a request records the decision without creating an attendee.

Organizer-created event invitations are managed from the event `Attendees` tab:

- Organizers with events write access can invite a registered platform user or enter an email
  address for someone who has not registered yet.
- For new invitees, email invitations should use the invitee's LF account primary email because LF
  SSO activates the placeholder by email. For existing users, select the registered platform user
  when possible; LF SSO identity reconciliation handles later LF email changes during login.
- Manual invitations are available for free RSVP events only, not ticketed events.
- Manual invitations are an organizer override for registration windows and capacity. Invitees can
  accept and answer required registration questions outside the public registration window.
- Pending invitations appear in the attendee table with invitation status and can be canceled
  before the invitee accepts.
- If an invitee rejects the invitation, the attendee row stays rejected and the same user cannot be
  invited to that event again.

![Add event flow](../screenshots/dashboard-group-add-event.png)

For complete mechanics, continue to:

- [Event Operations](event-operations.md)

To understand how attendees experience the published result, see
[Public Site Guide](public-site.md).

## Refunds: Operational Queue

`Refunds` brings the selected group's attendee requests, automatic refunds, and
provider processing into one operational list. It includes checkout-only refunds
that may not have a corresponding attendee row, as well as completed and rejected
history.

Use the views to focus the list:

- `Active` shows all unfinished refund work and is the default.
- `Needs attention` shows requests awaiting review, exhausted retries, and
  provider outcomes that require recovery.
- `Completed` shows refunded purchases and rejected requests.
- `All` shows the complete refund history.

You can search by attendee, event, or ticket and limit the list to one event.
Organizers with events write access can approve or reject pending requests and
retry exhausted non-terminal provider failures from the refund row. Read-only
roles can inspect every state but cannot use those actions.

When a provider outcome requires recovery, the refund row also offers
`Complete recovery`. Organizers with events write access can use it. Other
roles see the action disabled with an explanation of the requirement. After
arranging the attendee's refund outside OCG, the organizer records the external
refund reference and the evidence reviewed. OCG then completes any pending
local state, sends the completion notification when needed, and records the
recovery in the audit log.

The event `Attendees` tab shows refund status and the applicable request-review
and retry actions for attendees in that event. Recovery completion is available
only from the group-wide `Refunds` tab. Both views address the underlying
purchase directly, so historical purchases and checkout-only refunds do not
depend on a current attendance row.

## Audit: Logs

`AUDIT -> Logs` is the last section in the left dashboard menu. It provides a read-only record of
group dashboard activity for the selected group.

Coverage in this view includes:

- Group settings updates.
- Group team changes.
- Sponsor changes.
- Event lifecycle actions such as add, update, publish, unpublish, cancel, and delete.
- Check-ins, CFS submission reviews, and custom notification sends.

Rows are ordered by newest first by default, and you can switch the ordering to oldest first. You
can filter by `Action`, `Actor`, and date range, and pagination keeps the active filters applied.
When an audit row has extra metadata, such as a role or notification subject, `Details` opens a
popover with it.

For each entry, OCG shows the resource type plus the current resource name. If the resource no
longer exists, the audit entry still remains and falls back to the stored resource identifier.

This screen is group-dashboard focused, but some overlapping actions, such as `group_updated`,
can also appear in the community dashboard audit view when they match that dashboard's accepted
scope.
