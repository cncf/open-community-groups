<!-- markdownlint-disable MD013 -->

# User Dashboard Guide

Think of the User Dashboard as your home base inside OCG. It brings groups, upcoming events,
profile, badges, invitations, proposal writing, and submission tracking into one place so moving
from participant to speaker feels smooth.

For a fast end-to-end walkthrough first, use
[Quickstart](../getting-started/quickstart.md).

Path: [/dashboard/user](/dashboard/user ':ignore')

**Sections:**

- [User Dashboard Structure](#user-dashboard-structure)
- [My Groups](#my-groups)
- [My Events: Upcoming Participation](#my-events-upcoming-participation)
- [Profile: Public Identity](#profile-public-identity)
- [Badges: Portable Credentials](#badges-portable-credentials)
- [Invitations: Access and Attendance](#invitations-access-and-attendance)
- [Session Proposals: Reusable Talks](#session-proposals-reusable-talks)
- [Submissions: Track and Respond](#submissions-track-and-respond)
- [Audit: Logs](#audit-logs)
- [Recommended Working Rhythm](#recommended-working-rhythm)

## User Dashboard Structure

The dashboard is organized into eight areas:

- [My Groups](/dashboard/user?tab=groups ':ignore')
- [My Events](/dashboard/user?tab=events ':ignore')
- [Profile](/dashboard/user?tab=account ':ignore')
- [Badges](/dashboard/user?tab=badges ':ignore')
- [Invitations](/dashboard/user?tab=invitations ':ignore')
- [Session proposals](/dashboard/user?tab=session-proposals ':ignore')
- [Submissions](/dashboard/user?tab=submissions ':ignore')
- [Logs](/dashboard/user?tab=logs ':ignore')

Each area supports a different part of your participation in OCG: groups, events, profile,
portable credentials, access, proposals, submissions, and audit visibility.

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

`My Events` is your personal queue of upcoming events where you already have an active role.

Each row includes:

- Event title with a direct link to the public event page.
- Event location.
- Event date and time.
- Your participation roles in that event (`Attendee`, `Host`, `Speaker`, or multiple roles).
- Your attendance status when action is still needed, such as `Payment pending` or
  `Registration pending`.

When a row is marked `Payment pending`, use the row actions menu to complete checkout while the
ticket hold is still active, even if public registration closes after checkout started. When a row
is marked `Registration pending`, use the row actions menu to complete the event's registration
questions. You can update submitted answers from the same menu before the event starts while
registration is open, while an active checkout hold exists, or when an organizer invited you
manually.

If organizers configured a registration window, new public registration actions are disabled
outside that window. Organizer-created manual invitations and active checkout holds are the
exceptions for completing required registration questions from `My Events`.

The list includes only upcoming published events; canceled events and events from inactive or
deleted groups are excluded. Rows are ordered by date ascending, so the next event appears first.

![User profile area](../screenshots/dashboard-user-my-events.png)

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

When a community or group invites you to help run operations, or an organizer
invites you to attend an event, the invitation appears here. Accepting an
invitation updates your access or confirms your event attendance.

Both community/group team invites and event invitations move through the same statuses:
invitation sent, accepted, or rejected. Invitation rows include the role that will be assigned on
acceptance. Keep in mind that pending team invites do not grant dashboard access until accepted,
and pending event invitations do not make you an attendee until accepted.

When someone invites you to a team, you receive an in-app and email invitation with a direct path
to accept or decline.

When someone invites you to an event by email, sign in with LF SSO. If you do not already have an
OCG account, use the LF account whose primary email matches the invited address. Existing LF-linked
OCG accounts can still be recognized by LF SSO identity after an LF email change. If you cannot
accept an invitation, ask the site administrators to reconcile the account records.

After you accept an invitation, this is what typically happens:

1. Access is granted to the related scope.
2. The assigned community/group role becomes active for permission checks.
3. Event invitations become confirmed attendance and send the normal event confirmation.
4. Pending invitation state clears.
5. A refresh or re-login may be needed before navigation updates.

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
