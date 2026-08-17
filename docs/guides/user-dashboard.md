<!-- markdownlint-disable MD013 -->

# User Dashboard Guide

Think of the User Dashboard as your home base inside OCG. It brings groups, upcoming events,
attendee check-in credentials, profile, badges, invitations, proposal writing, and submission
tracking into one place so moving from participant to speaker feels smooth.

For a fast end-to-end walkthrough first, use
[Quickstart](../getting-started/quickstart.md).

Path: [/dashboard/user](/dashboard/user ':ignore')

**Sections:**

- [User Dashboard Structure](#user-dashboard-structure)
- [My Groups](#my-groups)
- [My Events: Upcoming Participation](#my-events-upcoming-participation)
- [Check-In: Attendee Credentials](#check-in-attendee-credentials)
- [Purchases and Financial Documents](#purchases-and-financial-documents)
- [Profile: Public Identity](#profile-public-identity)
- [Badges: Portable Credentials](#badges-portable-credentials)
- [Invitations: Access and Attendance](#invitations-access-and-attendance)
- [Session Proposals: Reusable Talks](#session-proposals-reusable-talks)
- [Submissions: Track and Respond](#submissions-track-and-respond)
- [Audit: Logs](#audit-logs)
- [Recommended Working Rhythm](#recommended-working-rhythm)

## User Dashboard Structure

The dashboard is organized into ten areas:

- [My Groups](/dashboard/user?tab=groups ':ignore')
- [My Events](/dashboard/user?tab=events ':ignore')
- [Check-In](/dashboard/user?tab=check-in ':ignore')
- [Purchases & documents](/dashboard/user?tab=purchases ':ignore')
- [Profile](/dashboard/user?tab=account ':ignore')
- [Badges](/dashboard/user?tab=badges ':ignore')
- [Invitations](/dashboard/user?tab=invitations ':ignore')
- [Session proposals](/dashboard/user?tab=session-proposals ':ignore')
- [Submissions](/dashboard/user?tab=submissions ':ignore')
- [Logs](/dashboard/user?tab=logs ':ignore')

Each area supports a different part of your participation in OCG: groups, events, attendee
check-in, profile, portable credentials, access, proposals, submissions, and audit visibility.

## My Groups

`My Groups` lists active groups where you are a member or an accepted group team member. The
top-right user menu also links directly to this section.

Each row includes:

- Group name with a direct link to the public group page.
- Community name.
- The date your membership or team relationship started.
- Your role in the group: member, team member, or both.
- A row actions menu.

Use `Leave group` in the row actions menu to remove your group membership after confirmation.
The action is disabled when you only belong to the group through a team role because team access
is managed separately. If you have both relationships, leaving removes the membership while the
accepted team relationship keeps the group in the list.

Rows are ordered by group name.

## My Events: Upcoming Participation

`My Events` is your personal queue of upcoming events where you have an active role, an active
direct checkout hold, or an event offer.

Each row includes:

- Event title with a direct link to the public event page.
- Event location.
- Event date and time.
- Your participation roles in that event (`Attendee`, `Event offer`, `Host`,
  `Speaker`, or multiple roles).
- Your attendance status when action is still needed, such as `Payment pending` or
  `Registration pending`.
- A `Refund rejected` badge and the organizer's full reason when a refund request was rejected. A
  legacy rejection without a reason still shows the badge.

When a row is marked `Payment pending`, use the row actions menu to complete checkout while the
ticket hold is still active, even if public registration closes after checkout started. You can
also cancel checkout from the same menu to release the hold. A pending payment does not describe
you as an attendee unless you already have a separate confirmed attendance role. When a row is
marked `Registration pending`, use the row actions menu to complete the event's registration
questions. You can update submitted answers from the same menu before the event starts while
registration is open, while an active checkout hold exists, or when an organizer invited you
manually.

An `Event offer` row links to the Invitations tab, which owns claim, decline,
checkout resume, and checkout cancellation actions. An active offer does not
describe you as an attendee until a free claim completes or paid checkout is
confirmed.

If organizers configured a registration window, new public registration actions are disabled
outside that window. Organizer offers and active checkout holds are the
exceptions for completing required registration questions from `My Events`.

The list includes only upcoming published events; canceled events and events from inactive or
deleted groups are excluded. Rows are ordered by date ascending, so the next event appears first.
Expired checkout holds disappear from the list unless you have another active role in the event;
hold expiration is reflected when the dashboard content next loads or refreshes.

![User profile area](../screenshots/dashboard-user-my-events.png)

## Check-In: Attendee Credentials

`Check-In` shows your personal QR code for each current or upcoming event where you are a
confirmed attendee. Open an event card and present the code to an organizer when you arrive. The
card remains available after check-in so another scan can safely report that you were already
checked in.

The mobile dashboard entry screen links to Check-In. On larger screens, open the section directly
at [/dashboard/user?tab=check-in](/dashboard/user?tab=check-in ':ignore'). Canceled, unpublished,
unscheduled, and past events are excluded.

## Purchases and Financial Documents

`Purchases & documents` is the durable history for paid tickets. Unlike `My
Events`, it includes completed and refunded purchases for past and canceled
events.

Each row shows the event, ticket, fiscal-sponsor seller, amount paid, purchase
or refund status, and available provider documents. Open invoice and issued
credit-note links in a new tab. A processing label means Stripe has not issued
the document yet or OCG is still reconciling its current link.

Use this dashboard history to access documents for upcoming, past, and canceled
events. Free and discounted-to-zero purchases do not create Stripe invoices or
credit notes.

## Profile: Public Identity

`Profile` is not just cosmetic. Organizers, co-speakers, and reviewers use this information
when collaborating with you.

You can maintain:

- Personal details: name, timezone, company, title, photo, bio, interests.
- Location: city and country.
- Social links: website, LinkedIn, Bluesky, X, Facebook, GitHub.
- Notification preferences.

Field requirements and limits are shown inline in the dashboard forms while you edit.

Notification preferences deserve a note: `Receive optional notifications` controls broader
announcements such as new event announcements, event reminders, and custom messages from
organizers. Turning it off does not disable account, invitation, registration, speaker, refund,
waitlist, cancellation, or reschedule updates.

![User profile area](../screenshots/dashboard-user-profile.png)

## Badges: Portable Credentials

`Badges` contains the active credentials that groups have awarded to you. From here, you can choose
which badges appear on your public profile, set their order, open a shareable public credential
page, export a portable PNG, or permanently revoke a credential.

For sharing options, compatible-system imports, verification, privacy, and revocation behavior,
follow [User Badge Operations](badges.md#user-badge-operations) in the Badges Guide.

## Invitations: Access and Attendance

This tab contains community and group team invitations plus active event
admission offers. Event offers can come from an organizer invitation, an
approved ticket request, or a ticket waiting list.

Community and group invitation rows show the role granted after acceptance.
Pending team invitations do not grant dashboard access.

Event offer rows show:

- The event, source, assigned ticket tier or RSVP, and displayed price.
- The exact offer deadline in the event timezone.
- Existing ticket-request answers and any registration questions required at
  claim time.
- `Claim offer`, plus `Decline`.
- `Continue to checkout` and `Cancel checkout` when a paid checkout hold exists.

The displayed ticket price is finalized on first claim. Checkout retries keep
that confirmed snapshot. Before a claim completes, no charge or attendance has
been created.

When someone invites you to a team, you receive an in-app and email invitation with a direct path
to accept or decline.

When someone invites you to an event by email, sign in with LF SSO. If you do not already have an
OCG account, use the LF account whose primary email matches the invited address. Existing LF-linked
OCG accounts can still be recognized by LF SSO identity after an LF email change. If you cannot
accept an invitation, ask the site administrators to reconcile the account records.

After you accept a team invitation:

1. Access is granted to the related scope.
2. The assigned community/group role becomes active for permission checks.
3. Pending invitation state clears.
4. A refresh or re-login may be needed before navigation updates.

After an event offer is claimed, a free ticket or RSVP completes inside OCG.
A positive ticket price continues through hosted checkout. Attendance and the
normal event confirmation are created only after free completion or paid
confirmation.

If organizer dashboards still do not appear, see
[Choose Your Dashboard](../getting-started/choose-dashboard.md) and
[Troubleshooting](../support/troubleshooting.md).

![Invitations area](../screenshots/dashboard-user-invitations.png)

## Session Proposals: Reusable Talks

`Session proposals` is where you manage talk proposals you can reuse across
events. This helps you keep your talk content consistent while submitting to
different events.

![Session proposals list](../screenshots/dashboard-user-session-proposals-list.png)

Create flow:

1. Click `New proposal`.
2. Complete required fields (`Title`, `Level`, `Duration`, `Description`).
3. Optionally add a co-speaker by username search.
4. Save and reuse the proposal in eligible event CFS flows.

For event-side CFS controls and reviewer operations, see
[Event Operations](event-operations.md).

![New proposal modal](../screenshots/dashboard-user-new-proposal-modal.png)

### Proposal Status Model

Every proposal has one of these base statuses:

- `Ready for submission`
- `Awaiting co-speaker response`
- `Declined by co-speaker`

On top of the base status, derived badges may also appear:

- `Submitted` (used in one or more event submissions).
- `Linked` (already tied to an approved session).

### When a Proposal Gets Locked

!> `Linked` proposals cannot be edited. `Submitted` proposals can still be
updated, but delete and some co-speaker changes are blocked.

- `Linked` is a hard lock. Once a proposal is linked to an accepted event session, it is treated as
  delivery content and can no longer be edited in place.
- `Submitted` is a partial lock. You can still improve most proposal content, but some operations
  become constrained because the proposal is already in review history:
  - Delete is blocked.
  - Co-speaker changes are restricted after submission.

There are also status-related submission locks: `Awaiting co-speaker response` and
`Declined by co-speaker` are not full edit locks, but they do block CFS submission eligibility
until co-speaker state is resolved.

### Co-Speaker Invitations

If another speaker invites you as co-speaker, OCG shows an in-app alert with actions to view,
accept, or decline. This keeps proposal ownership clear without hidden side effects.

Co-speaker invite statuses appear with your proposal workflow: pending, accepted, or declined.

## Submissions: Track and Respond

Once you submit a proposal from an event page, `Submissions` becomes your control center for
review progress.

![Submissions area](../screenshots/dashboard-user-submissions-list.png)

The statuses you will see most often are:

- `Not reviewed`
- `Information requested`
- `Approved`
- `Rejected`
- `Withdrawn`

Available actions depend on status. `Resubmit` appears when the status is
`Information requested`. `Withdraw` stays available while the submission is active and not
finalized, and is blocked for finalized or linked outcomes.

When organizers change your submission review state, OCG sends an update message with the new
status and any action you need to take.

To understand where submission decisions are made, see
[Event Operations](event-operations.md).

## Audit: Logs

`AUDIT -> Logs` is the last section in the left dashboard menu. It provides an actor-based audit
trail for actions you performed from the user dashboard and account settings.

Coverage in this view includes:

- Invitation accept and reject actions.
- Session proposal create, update, delete, and co-speaker invitation decisions.
- Submission resubmits and withdrawals.
- Account profile and password updates.

Rows are ordered by newest first by default, and you can switch the ordering to oldest first. You
can filter by `Action` and date range, and pagination keeps the active filters applied. When an
audit row has extra metadata, `Details` opens a popover with it.

Note that this screen shows actions performed by the signed-in user; it does not try to list
unrelated actions performed by other people against your account.

## Recommended Working Rhythm

?> Review this list regularly so invitations and submission deadlines do not
catch you by surprise.

1. Keep profile current (especially bio, timezone, and links).
2. Use `My Groups` to return to the communities where you participate.
3. Track `My Events` to stay ahead of upcoming commitments.
4. Clear invitations quickly so role-based access stays accurate.
5. Build reusable proposals before deadlines.
6. Submit to events where CFS is open.
7. Watch `Submissions` and respond fast when information is requested.
