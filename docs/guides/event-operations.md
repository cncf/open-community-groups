<!-- markdownlint-disable MD013 -->

# Event Operations

This guide covers the full event lifecycle in
[Group Dashboard -> Events](/dashboard/group?tab=events ':ignore'): draft creation, configuration,
publishing, delivery-day execution, and controlled retirement.

For scope boundaries and non-event responsibilities, pair this with
[Group Dashboard Guide](group-dashboard.md).

**Sections:**

- [Lifecycle Model](#lifecycle-model)
- [Authorization Model](#authorization-model)
- [Events List: Work Queue](#events-list-work-queue)
- [Add Event: Draft First](#add-event-draft-first)
- [Event Editor Tabs](#event-editor-tabs)
- [CFS Workflow (End to End)](#cfs-workflow-end-to-end)
- [Automatic Meeting Creation](#automatic-meeting-creation)
- [Tickets, Discounts, and Refunds](#tickets-discounts-and-refunds)
- [Attendance, Invitation, and Waitlist Operations](#attendance-invitation-and-waitlist-operations)
- [Publish, Unpublish, Cancel, Delete](#publish-unpublish-cancel-delete)
- [Public Event Result](#public-event-result)
- [Event-Day Checklist](#event-day-checklist)

## Lifecycle Model

Treat event operations as a staged workflow, not one big form submission:

1. Build a complete and trustworthy draft.
2. Publish only when attendee-facing data is ready.
3. Run delivery-day operations (attendance, check-in, communication).
4. Retire intentionally (unpublish, cancel, or delete).

When phase 1 is done well, every downstream step is faster and safer.

## Authorization Model

Event write operations require events write access. This is granted by the group `admin` and
`events-manager` roles, and by the community `admin` and `groups-manager` roles. Read-only roles
can still view event data but cannot change it.

When your role cannot perform an operation, the event action controls are disabled in the UI, and
OCG enforces the same permissions on every event change.

![Group disabled form](../screenshots/dashboard-group-permissions-role.png)

## Events List: Work Queue

[Events](/dashboard/group?tab=events ':ignore') is your organizer queue. `Upcoming events` and `Past events`
help you separate work that needs intervention now from historical cleanup.

From each row, you can:

- Create with [Add event](/dashboard/group?tab=events ':ignore').
- Open edit mode.
- Open the public event page (when available).
- Publish/unpublish.
- Cancel.
- Delete.

Each event is in one of three states: `Draft` while it is still being authored, `Published` once
it is live for public participation, and `Canceled` when it is no longer running. If a canceled
event was published, its public page remains available with canceled-state messaging.

![Events operations list](../screenshots/dashboard-group-events.png)

## Add Event: Draft First

The safest pattern is draft-first, publish-second.

Recommended flow:

1. Click `Add Event`.
2. Optionally copy an earlier event to reuse structure.
3. Complete each editor tab.
4. Save.
5. Publish only after a full quality pass.

Copying is intentionally partial so stale logistics are not carried forward:

?> After copying an event, run a quick logistics sweep before publishing.
Time-bound and meeting-specific fields are intentionally not carried forward.

- Start/end dates are cleared.
- Registration window dates are cleared.
- Sessions are not copied.
- Meeting links are not copied.
- Some older host/speaker fields may need manual cleanup.

![Add event editor](../screenshots/dashboard-group-add-event.png)

## Event Editor Tabs

The editor is organized so you can move from identity, to schedule, to speakers, to operations.

### Details

In this tab, you define attendee-facing identity and enrollment posture: name, event type,
category, description, branding assets, registration toggle, tags, and optional links.

Event category options come from the defined community's
[Event Categories](/dashboard/community?tab=event-categories ':ignore') tab.

Publish readiness checks in this tab:

- Name, type, category, and description are complete and clear.
- Branding is consistent with group/community standards.
- Registration policy matches expected demand.

Ticketing is configured in the `Tickets` tab. `Ticket Types`
define tier names, public or invitation-only availability, seat counts, and
date-based price windows. `Event Currency` and `Discount Codes` apply only to
paid-capable events.

These are the ticketing rules to keep in mind:

- Every event has at least one ticket type. New events begin with a free,
  public `General Admission` tier with 500 seats.
- Free-only events require no payment provider, group recipient,
  currency, or discount codes.
- Any positive current or future price window makes the event paid-capable,
  including inactive and invitation-only tiers.
- Multiple ticket types can exist on the same event.
- Early-bird pricing is modeled as multiple price windows on the same ticket type.
- Events automatically derive total capacity from ticket seat counts. The last
  ticket type cannot be removed.
- Public tiers support direct enrollment, approval requests, or per-tier
  waiting lists according to event mode.
- Invitation-only tiers are disclosed only to the recipient of an assigned
  offer.
- Positive prices require server payment configuration, a matching group
  recipient, and event currency.

Deployments upgrading legacy RSVP events automatically create a free, public
`General Admission` tier when an event has no ticket inventory. Existing finite
capacity is preserved or raised to cover occupied seats; previously unlimited
events receive 500 seats.

If your group is not payment-ready, keep every price window at zero. Complete
[Payments Setup](payments-setup.md) before configuring a positive price.

?> Accepted community admins with verified email addresses receive an email when a non-test paid
event or paid recurring series is created, and when an existing non-test free event is changed to a
paid event.

Waitlist control also lives here:

- `Waitlist enabled` is an explicit event toggle.
- Waiting lists are tracked separately for each sold-out public tier.
- Increase or decrease capacity by changing ticket-type seat counts. A tier's
  seat count cannot be reduced below its current allocation.
- Waitlist cannot be combined with invitation review.
- If capacity is full and waitlist is off, the public page shows the event as sold out.
- If capacity is full and waitlist is on, people can join that tier's waiting
  list instead of starting checkout.

### Questions

Use the `Questions` tab to define registration questions for attendees. Supported question types
are free text, single select, and multi select. Select questions use organizer-defined options,
and each question can be marked required.

Registration questions are copied when you create an event from an existing event. After attendees
submit answers, or while active checkout holds exist, the questions become read-only so existing
attendee answers and in-progress checkouts cannot drift away from the question definitions.

Invitation review also lives here:

- `Require Invitation Approval` changes public ticket actions to
  `Request ticket`.
- Approval cannot be combined with waitlist, but it can be combined with free
  or paid ticketing.
- Public ticket requests preserve the selected tier. A fully private
  event accepts a generic request without disclosing private tiers.
- Pending requests do not reserve seats. Accepting a ticket request creates a
  time-limited offer when capacity and payment readiness allow it.
- A generic private request requires the organizer to assign an active
  invitation-only tier during acceptance.
- Disabling invitation review is blocked while pending requests exist.
- Accepted requests receive a time-limited offer that must be claimed. Free
  offers complete inside OCG; positive prices continue to hosted checkout.

Brand inheritance in event details mirrors the group model: if the event logo is not provided,
OCG falls back to the group logo, then the community logo; if the event banner or mobile banner
is not provided, OCG falls back to the group banner, then the community banner.

![Event details](../screenshots/dashboard-group-event-details.png)

### Date and Venue

This tab controls delivery constraints:

- Timezone, start, and end.
- Optional registration open and close dates.
- Recurrence for creating linked copies of a new event.
- Venue data for in-person/hybrid events.
- Online event details for virtual/hybrid events.
- 24-hour reminder toggle.

Timezone should be set first, then date/time. That avoids accidental scheduling drift and keeps
CFS windows aligned with the intended audience clock.

?> Set timezone first, then start/end timestamps, to avoid accidental schedule drift.

Registration windows are optional, but when configured they become the source of truth for
attendee-facing registration:

- `Registration Opens` controls when attendees can self-register, get tickets, request tickets,
  join the waitlist, or submit registration-question answers. It cannot be after the event start
  time.
- `Registration Closes` controls when those actions stop. It cannot be after the event start time.
  When both fields are set, it must be after `Registration Opens`.
- If only an open time is set, registration stays open until the event starts.
- If only a close time is set, registration is open immediately and closes at that time.
- Public event pages and notification templates show the configured window.
- Organizer offers are an override. Invitees can accept and answer required
  registration questions outside the public window.
- Active ticket checkout holds are also an override for completion only. Registration close stops
  new checkout starts, but attendees already holding a ticket can finish checkout and required
  registration questions until the hold expires.

When `Send Event Reminder` is enabled, OCG sends reminder messages about 24 hours before start
time.

When adding a new event, recurrence can create multiple linked events at once:

- `Just once` creates one event.
- `Weekly` creates additional events on the same weekday as the selected start date.
- `Every two weeks` creates additional events on the same weekday every other week.
- `Monthly` creates additional events on the same ordinal weekday, such as the third Monday.

For recurring events, set `Additional Events` to the number of extra linked events to create.
The maximum is `12`. OCG creates each occurrence as a separate individual event, sharing one
series identifier, and shifts event dates, registration windows, CFS windows, sessions, ticket
windows, and discount windows by the same schedule offset. Monthly recurrence skips months that do
not contain the same ordinal weekday.

After creation, each occurrence has its own event page, editor, attendees, submissions, sessions,
tickets, and operational state. `Publish`, `Unpublish`, `Cancel`, and `Delete` can target the
whole linked series, but editing event content is intentionally one event at a time.

![Event date and venue](../screenshots/dashboard-group-event-date.png)

### Hosts, Speakers, and Organizers

In this tab, you manage event-level people and sponsor attribution: adding hosts from any user
account on the site, adding visible speakers/presenters, and attaching event sponsors from
reusable sponsor records.

OCG also shows an `Organizers` section on the public event page. Organizers are snapshotted from
the accepted group team when the event is created, so later group team changes do not rewrite
existing event attribution. Use event hosts for people who should be explicitly highlighted as
running the event program.

This is where attendees understand who is running, organizing, and presenting the program.

Existing hosts and speakers can also receive badges from their row menus. Bulk actions award a
badge to all current hosts or to the deduplicated set of event-level and session-level speakers.
Save host, speaker, and session changes before awarding. For the complete contributor award flow,
see [Group Badge Management](badges.md#group-badge-management).

![Event hosts and speakers](../screenshots/dashboard-group-event-hosts.png)

### Sessions

Sessions turns approved content into an actual agenda. Here you create agenda rows with time
bounds, keep session times inside the event start/end, and link approved CFS submissions into the
schedule.

This tab is usually most useful once review outcomes are clearer and your schedule is taking
final shape.

![Event sessions](../screenshots/dashboard-group-event-sessions.png)

![Event add session](../screenshots/dashboard-group-event-add-session.png)

### CFS

This tab configures speaker intake: enabling or disabling CFS, setting open/close timestamps,
writing the CFS description shown on the event page, and defining optional labels
(tracks/topics/themes).

Label model tip: if you edit an existing label name, that rename affects submissions already using
that label.

?> Renaming a label updates existing submissions that already reference that label.

![Event CFS](../screenshots/dashboard-group-event-cfs.png)

## Tickets, Discounts, and Refunds

Public tickets are attendee-self-service from the event page.

Public ticket flow:

1. Attendee selects a ticket type.
2. Optional discount code is entered on the event page.
3. OCG creates a short seat hold.
4. Free tickets are completed immediately.
5. A positive final price redirects to hosted payment checkout.
6. Attendance is created immediately for free tickets, or after the payment provider confirms
   payment for paid tickets.

Ticket and discount data model:

- Ticket types are event-level, can be mixed free and paid, and can be public
  or invitation-only.
- Each ticket type can have one or more date-range price windows.
- Discount codes are event-level and support fixed-amount or percentage discounts.
- Discount codes can be limited by time window, remaining uses, or total available uses.
- Remaining uses are consumed by active holds and active purchases, then restored when a hold
  expires, a free ticket is released, or a refund is finalized.

Refunds follow a request-and-review model. Paid attendees do not use `Leave event`; they use
`Request refund` from the public event page instead. Organizers can review refund requests in
`Event -> Attendees` or the group dashboard `Refunds` tab and approve or reject them. Refund
requests must be submitted before the event starts, though organizers can still approve or reject
a request later if it was submitted before the start time. Approved refunds are full refunds only,
and rejecting a request leaves the attendee and ticket unchanged. A rejection requires a reason;
the attendee sees the same reason in their notification, on the event page, and in `My Events`.
Approval notes remain optional and organizer-only. Approval queues the provider refund; both
dashboard views show its progress until the refund completes or needs intervention.

Canceling an event is the other way a refund begins. OCG immediately cancels active attendance,
completes free-ticket refunds locally, and queues every paid ticket for a full provider refund.
The event remains canceled even if a provider attempt later needs retry or manual recovery.
After arranging an external refund for a terminal provider failure, an organizer with events write
access can complete that recovery from the group dashboard `Refunds` tab. Other roles see the
recovery action disabled with an explanation of the requirement.

Refund requests, approvals, rejections, and completed refunds are all written to audit logs.
Organizers are notified when attendees request refunds. Attendees are notified when a rejection
is recorded, including the rejection reason, or an approved or automatic paid refund has
completed.

Capacity is released immediately for a canceled free ticket. Paid capacity
remains allocated through refund-requested, provider-pending, and recovery
states, then releases after successful finalization or recorded manual
recovery. Reconciliation then allocates available inventory to the oldest
eligible queue entry.

### Attendance, Invitation, and Waitlist Operations

The dashboard separates confirmed attendees from people waiting for a seat or organizer approval.

On the organizer side, the tabs work like this:

- `Attendees` shows confirmed attendees plus organizer-created offer history.
- `Requests` shows approval requests, requested or assigned tiers, and approval
  offer history.
- `Waitlist` shows FIFO queue position for queued users and ticket offer
  history for promoted users.
- `Attendees`, `Requests`, and `Waitlist` keep search, filter, sort, and pagination state together
  while you refine the table.
- Canceling an event notifies attendees, speakers, and waitlisted users.
- Accepting or rejecting an invitation request is written to the audit log.
- Sending, canceling, accepting, or rejecting an organizer-created event invitation is written to
  the audit log.

Capacity changes drive automatic waitlist behavior:

- If an attendee leaves and inventory becomes available, OCG reconciles the
  oldest eligible waiting-list entry while registration is open.
- If you raise a ticket tier's seat count, reconciliation offers the new
  inventory to that tier's queue before direct checkout or organizer
  invitations use it.
- A queue head that cannot currently receive an offer because payment setup or
  current pricing is unavailable keeps first position. Later users and direct
  checkout cannot skip that person.
- If you later disable the waitlist, OCG stops accepting new waitlist sign-ups. People who were
  already on the waitlist remain queued and may still be promoted automatically when registration is
  open and attendee spots open up, for example after a cancellation or a capacity increase.
- Reconciliation creates a time-limited offer for each promoted user. It never
  moves someone directly from the waiting list into confirmed attendance.
- Attendee cancellation notifications are guaranteed: if OCG cannot queue the
  required cancellation notification, the attendance cancellation is not saved.
- Organizer invitations bypass public approval and registration windows, but
  never capacity or public-tier queue priority.
- Active offers reserve capacity until their displayed deadline. The claim
  window is at most 24 hours and is shortened by the event or registration
  deadline when necessary.
- Expiry, decline, or organizer cancellation releases the reservation and runs
  reconciliation. Declined or expired waitlist recipients lose that queue
  position and are not automatically requeued.
- Expired approval offers and organizer invitations can be reissued when the
  recipient remains eligible. Waiting-list offers cannot be manually reissued.

On the member side, these actions trigger notifications:

- Accepting an approval request creates a claimable offer.
- Claiming a free organizer offer confirms attendance and sends the normal
  event confirmation. A positive offer price starts hosted checkout.
- Joining the waitlist sends a waitlist confirmation notification.
- Leaving the waitlist sends a waitlist removal notification.
- Waitlist promotion sends an offer notification with the tier, displayed
  price, claim link, and exact deadline.
- Confirmation notifications caused by completing free organizer offers or
  completing pending registration questions are guaranteed: if OCG cannot
  queue the required notification, the attendance change is not saved.

Paid attendance behaves differently in a few ways:

- Paid tickets require payment before attendance is created.
- Checkout can only start while registration is open. If registration closes before a pending
  payment is completed, an active ticket hold can still be fulfilled until the hold expires.
- If checkout is interrupted, the public event page and user dashboard show
  `Continue to checkout` while the hold is active.
- Attendees can use `Cancel checkout` before payment completes to release the hold and choose a
  different ticket or discount code.
- Free ticket attendees can still leave the event themselves.
- Paid attendees request refunds instead of leaving directly.

### Submissions

This tab is the reviewer control center. From here you can filter by labels, sort by submission
time, rating count, or stars, open the review modal, and update status with reviewer feedback.

The reviewer-facing statuses are:

- `Not reviewed`
- `Information requested`
- `Approved`
- `Rejected`

![Event submissions](../screenshots/dashboard-group-event-submissions.png)

#### Rating submissions

Reviewers can rate each submission on a 1–5 star scale with an optional comment. Ratings
are internal only — speakers never see ratings or rating notes. The review modal shows a
dedicated `Ratings` tab where you can set, update, or clear your rating. Other reviewers'
ratings and comments are visible in the same tab so the team can compare assessments.

The submissions list displays the average rating and total rating count for each entry.
Use the sort options (by stars or rating count) to surface the strongest or most-reviewed
submissions quickly.

When a reviewer update requires notifying the speaker, OCG sends a submission update message.

![Event submissions ratings](../screenshots/dashboard-group-event-submissions-ratings.png)

### Attendees

This tab supports delivery-day execution. From here you can:

- Review the attendee list and enrollment timing.
- Run manual check-in.
- Open the attendee actions menu to generate a check-in QR code for on-site flow.
- Cancel confirmed free attendance for future active events.
- Open the attendee actions menu to invite attendees with an assigned ticket
  type.
- Award badges to all attendees, checked-in attendees, selected attendees, or one attendee.
- Send all-attendee or selected-attendee operational emails.
- Download the attendee list or attendee answers as CSV.

Manual check-in bypasses attendee self-check-in timing windows, but the person must already be
registered as an attendee and the event must still be published or active.

The `Award badge` menu opens the badge picker for the chosen attendee set. Selection mode keeps
chosen attendees while you change table filters, sorting, or pages. For eligibility, duplicate
award, and revocation behavior, see
[Group Badge Management](badges.md#group-badge-management).

`Cancel attendance` is available from confirmed attendee row actions for future, active events
when the attendee does not have a paid ticket. OCG marks the attendance as canceled, notifies the
attendee, and can promote the next waitlisted user when a seat opens. Paid attendees stay on the
refund workflow instead. Canceled attendance remains in the event history rather than being
deleted.

The attendee actions menu contains event-level attendee actions and exports. `Show check-in QR code`
opens a QR code for the public check-in flow. `Invite attendee` is available
when you have event write access. Invitations require an active,
currently priced tier with capacity. You can select a registered platform user
or enter an email address. For new invitees, use their LF account primary email
because LF SSO activates the email invitation by that address. For existing
users, select the registered platform user when possible; LF-linked accounts
can keep logging in after an LF email change because OCG reconciles them by LF
SSO identity. Active offers show their tier, state, and deadline and can be
canceled. Expired organizer invitations can be reissued when eligible.

The same attendee actions menu includes two CSV exports: `Attendees list CSV` exports attendee name,
company, title, and whether the confirmed attendee was manually invited; `Attendees list CSV
(including answers)` adds one column per registration question. Row actions also include
`View answers` when an attendee has submitted registration answers.

The attendees table can be searched by attendee identity and visible profile details, including
company and title. It can also be sorted by attendee name or enrollment date, and filtered by
enrollment status, check-in status, title presence, or ticket type. The `Enrollment status` selector
groups broad views separately from exact statuses. `Current enrollments` includes confirmed,
checkout-pending, invitation-pending, and registration-pending enrollments. `Enrollment history`
includes canceled attendance plus canceled, declined, and expired invitations. Select an exact
status or `All enrollments` when you need a narrower or complete audit. Check-in filters apply only
to confirmed attendees. Canceled events open on `All enrollments` so organizers can see the full
audience and paid-refund progress.

The invitation requests table can be sorted by requester or request date, filtered by request status
or title presence, and reset to `All` statuses when you need to audit accepted and rejected requests.
The waitlist table can be sorted by entry name or joined date and filtered by title presence; the
queue column still shows the FIFO promotion order. An exhausted transient refund can be retried from
its attendee row; terminal provider failures remain visible for operator recovery.

`Send email` in this tab sends operational updates to attendees who receive optional notifications.
Organizers can send to all eligible attendees, including confirmed attendees and attendees who still
need to complete registration questions, or enter email selection mode to choose eligible attendees
directly from the table. Eligible attendee rows also include `Send email` for starting with that
attendee selected. The email form includes a required `Subject`, defaults it to
`{group name}: {event name}`, and sends the message body as plain text.

![Event attendees](../screenshots/dashboard-group-event-attendees.png)

## CFS Workflow (End to End)

CFS spans organizer setup, speaker submission, and review loop. Treat it as one connected system.

1. Organizer configures CFS in the event editor.
2. Organizer publishes the event.
3. Speaker prepares reusable proposals in
   [User Dashboard -> Session proposals](/dashboard/user?tab=session-proposals ':ignore').
4. Speaker submits from the event page CFS modal.
5. Organizer reviews in [Group Dashboard -> Event -> Submissions](/dashboard/group?tab=events ':ignore').
6. Speaker tracks outcomes in
   [User Dashboard -> Submissions](/dashboard/user?tab=submissions ':ignore').
7. Approved submissions are scheduled in `Sessions`.

![Session proposals list](../screenshots/dashboard-user-session-proposals-list.png)

![User submissions list](../screenshots/dashboard-user-submissions-list.png)

To submit, these requirements must be met:

!> CFS submission requires a published event, enabled/open CFS, and an eligible proposal.
Duplicate proposal submission to the same event is blocked.

- Event must be published.
- CFS must be enabled.
- CFS window must be open.
- Proposal must be eligible for submission.
- Duplicate submission of the same proposal to the same event is blocked.
- Labels must belong to that event's label set.

The review loop works in both directions: `Information requested` asks the speaker for changes
before re-review, `Resubmit` is used after the requested changes are addressed, and `Withdrawn`
is speaker-initiated and typically ends active review.

Every review-side change that should reach the speaker is sent as a submission update message.

For submitter-side perspective, see [User Dashboard Guide](user-dashboard.md).

## Automatic Meeting Creation

Automatic meetings are configured in `Date and Venue -> Online event details`.
You can either use your own manual meeting link or let OCG create/manage a meeting automatically.

How automatic mode works:

- Choose `Create meeting automatically`.
- Select provider (currently `Zoom`).
- Optionally add host emails for coordination.
- Leave `Record meeting` enabled when OCG should ask the provider to record automatically, or
  turn it off when the event should not be recorded.
- Save the event.
- Publish the event to trigger meeting creation.
- Wait for sync; join link/password appear once ready.
- Meetings are automatically ended when the configured end time is reached.

Requirements for automatic mode:

!> Automatic meetings are supported only for `virtual` and `hybrid` events and require valid
schedule/capacity constraints. Manual and automatic meeting modes cannot be used together.

- Event type is `virtual` or `hybrid`.
- Start and end are set, with end after start.
- Duration is within provider limits (5 to 720 minutes).
- Event capacity is set.
- Capacity does not exceed configured provider participant limit.
- Manual meeting links are not used at the same time.

Important limitations and behavior:

!> Switching meeting modes can replace or remove meeting details.
Constraint violations can disable automatic mode until fixed.

- In-person events cannot use automatic meetings.
- Due to current technical limitations, host controls are not available in
  automatically created Zoom meetings.
- Switching automatic to manual can remove auto-created meeting details.
- Switching manual to automatic can replace existing manual links.
- Event and session recording links for automatic meetings can be replaced later
  with processed uploads hosted elsewhere.
- `Record meeting` controls whether automatically created Zoom event and session meetings request
  cloud recording.
- Zoom can send multiple raw recording URLs when participants join before or
  after the main meeting. Review the raw URLs and copy the correct one into the
  final public recording URL field, or use a processed upload.
- Event and session recordings are not public by default. Enable
  `Publish recording publicly` to show the final public recording URL.
- After an automatic meeting or session has started, OCG keeps an already synced provider meeting
  settled instead of re-queueing provider updates for a past start time.
- Schedule or type changes can disable automatic mode if constraints are no longer met.
- If sync fails, meeting errors surface in the editor until resolved.
- In deployments without automatic-meeting support, only manual meeting URL fields are available.

![Events automatic meeting](../screenshots/dashboard-group-event-automatic-meeting.png)

## Publish, Unpublish, Cancel, Delete

Each of these actions serves a different intent. `Publish` makes the event publicly available,
while `Unpublish` hides it without changing its canceled state. `Cancel` marks the event as not
proceeding while keeping an already published page available as canceled, and `Delete`
permanently removes it from normal operations.

Cancellation is irreversible. Its confirmation explains that active attendees will be canceled,
free tickets will be closed locally, and every paid ticket will be queued for a full refund.
Unpublishing does not cancel attendance or start refunds. Deleting does not start refunds either:
future events must be canceled first, and deletion stays disabled while checkout, refund, or refund
recovery work is unresolved. Unused never-published drafts and completed past events can be deleted
without cancellation.

Notification behavior differs per action:

!> `Publish` and `Cancel` can notify large participant sets.
`Unpublish` and `Delete` do not send broad attendee updates in this flow.

- `Publish` on a future unpublished event can notify group members/team members and listed
  speakers.
- `Cancel` on a future published event notifies attendees, speakers, and waitlisted users.
- Series `Publish` and `Cancel` actions aggregate affected events into grouped notifications
  instead of sending one email per event. Aggregate notifications include links to the affected
  events, but do not attach individual calendar files.
- Rescheduling a future published event can notify attendees and speakers when the start or end
  time changes by at least 15 minutes. Waitlisted users are not included in reschedule notices.
- `Unpublish` and `Delete` do not send broad attendee updates in this flow.

For `Publish`, `Cancel`, and event-editor updates that require publish,
cancellation, or reschedule notifications, the notification handoff is guaranteed: if OCG cannot queue
the required notifications, the event change is not saved. A later payment-provider refund failure
does not reverse an event cancellation; it remains visible for retry or recovery.

Automatic meetings follow these actions too: `Publish` triggers creation/sync for configured
automatic meetings (event and session meetings), while `Unpublish`, `Cancel`, and `Delete`
trigger removal/sync for them.

If an event belongs to a recurring series, `Publish`, `Unpublish`, `Cancel`, and `Delete` ask
whether to apply the action to only the selected event or the linked series. Series cancellation
targets only occurrences that are not completed or already canceled. Series actions are applied
atomically: either every selected event is updated, or none are.

Other event edits remain individual-event operations. Updating details, dates, venue, online
meeting configuration, hosts, speakers, sponsors, sessions, CFS settings, tickets, discounts, or
attendee settings changes only the event you are editing, even when it belongs to a recurring
series.

Use the least destructive action that matches your operational goal.

![Events actions](../screenshots/dashboard-group-events-actions.png)

## Public Event Result

The public event page is the delivery surface of all organizer decisions: enrollment controls, logistics,
CFS visibility, and final agenda experience. You can reach it through [Explore](/explore ':ignore').

For attendee/member perspective, see [Public Site Guide](public-site.md).

![Public event page](../screenshots/event-page.png)

## Event-Day Checklist

?> Run this checklist shortly before start time to catch delivery issues early.

1. Confirm attendee table loads in the `Attendees` tab.
2. Open QR flow and validate the check-in URL.
3. Test one manual check-in path.
4. Prepare attendee email template for urgent updates.
5. Re-verify schedule and meeting links before start.
