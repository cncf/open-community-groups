# Event Operations

This guide covers the full event lifecycle in
[`Group Dashboard -> Events`](/dashboard/group?tab=events ':ignore'): draft creation, configuration,
publishing, delivery-day execution, and controlled retirement.

For scope boundaries and non-event responsibilities, pair this with
[Group Dashboard Guide](group-dashboard.md).

**Sections:**

- [Lifecycle Model](#lifecycle-model)
- [Events List: Work Queue](#events-list-work-queue)
- [Add Event: Draft First](#add-event-draft-first)
- [Event Editor Tabs](#event-editor-tabs)
- [CFS Workflow (End to End)](#cfs-workflow-end-to-end)
- [Automatic Meeting Creation](#automatic-meeting-creation)
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

## Events List: Work Queue

[`Events`](/dashboard/group?tab=events ':ignore') is your organizer queue. `Upcoming events` and `Past events`
help you separate work that needs intervention now from historical cleanup.

From each row, you can:

- Create with [Add event](/dashboard/group/events/add ':ignore').
- Open edit mode.
- Open the public event page (when available).
- Publish/unpublish.
- Cancel.
- Delete.

State intent:

- `Draft`: still being authored.
- `Published`: live for public participation.
- `Canceled`: visible as canceled and no longer running.

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

- Start/end dates are cleared.
- Sessions are not copied.
- Meeting links are not copied.
- Some older host/speaker fields may need manual cleanup.

![Add event editor](../screenshots/dashboard-group-add-event.png)

## Event Editor Tabs

The editor is organized so you can move from identity, to schedule, to speakers, to operations.

### Details

In this tab, you define attendee-facing identity and enrollment posture: name, event type,
category, description, branding assets, capacity, registration toggle, tags, and optional links.

Publish readiness checks in this tab:

- Name, type, category, and description are complete and clear.
- Branding is consistent with group/community standards.
- Capacity and registration policy match expected demand.

Brand inheritance model in event details:

- If event logo is not provided, OCG falls back to group logo, then community logo.
- If event banner or mobile banner is not provided, OCG falls back to group banner, then
  community banner.

### Date and Venue

This tab controls delivery constraints:

- Timezone, start, and end.
- Venue data for in-person/hybrid events.
- Online event details for virtual/hybrid events.
- 24-hour reminder toggle.

Timezone should be set first, then date/time. That avoids accidental scheduling drift and keeps
CFS windows aligned with the intended audience clock.

When `Send Event Reminder` is enabled, OCG sends reminder messages about 24 hours before start
time.

### Hosts and Speakers

In this tab, you manage event-level people and sponsor attribution:

- Add hosts from any user account on the site.
- Add visible speakers/presenters.
- Attach event sponsors from reusable sponsor records.

This is where attendees understand who is running and presenting the program.

### Sessions

Sessions turns approved content into an actual agenda:

- Create agenda rows with time bounds.
- Keep session times inside event start/end.
- Link approved CFS submissions into the schedule.

This tab is usually most useful once review outcomes are clearer and your schedule is taking
final shape.

### CFS

This tab configures speaker intake:

- Enable/disable CFS.
- Set open/close timestamps.
- Write CFS description shown on the event page.
- Define optional labels (tracks/topics/themes).

Label model tip: if you edit an existing label name, that rename affects submissions already using
that label.

### Submissions

This tab is the reviewer control center:

- Filter by labels.
- Sort by submission time, rating count, or stars.
- Open review modal.
- Update status and add reviewer feedback.

Reviewer-facing statuses are:

- `Not reviewed`
- `Information requested`
- `Approved`
- `Rejected`

#### Rating submissions

Reviewers can rate each submission on a 1–5 star scale with an optional comment. Ratings
are internal only — speakers never see ratings or rating notes. The review modal shows a
dedicated `Ratings` tab where you can set, update, or clear your rating. Other reviewers'
ratings and comments are visible in the same tab so the team can compare assessments.

The submissions list displays the average rating and total rating count for each entry.
Use the sort options (by stars or rating count) to surface the strongest or most-reviewed
submissions quickly.

When a reviewer update requires notifying the speaker, OCG sends a submission update message.

### Attendees

This tab supports delivery-day execution:

- Review attendee list and RSVP timing.
- Run manual check-in.
- Generate check-in QR code for on-site flow.
- Send attendee-wide operational emails.

Manual check-in bypasses attendee self-check-in timing windows, but the person must already be
registered as an attendee and the event must still be published or active.

`Send email` in this tab sends operational updates to attendees.

## CFS Workflow (End to End)

CFS spans organizer setup, speaker submission, and review loop. Treat it as one connected system.

1. Organizer configures CFS in the event editor.
2. Organizer publishes the event.
3. Speaker prepares reusable proposals in
   [`User Dashboard -> Session proposals`](/dashboard/user?tab=session-proposals ':ignore').
4. Speaker submits from the event page CFS modal.
5. Organizer reviews in [`Group Dashboard -> Event -> Submissions`](/dashboard/group?tab=events ':ignore').
6. Speaker tracks outcomes in
   [`User Dashboard -> Submissions`](/dashboard/user?tab=submissions ':ignore').
7. Approved submissions are scheduled in `Sessions`.

![Session proposals list](../screenshots/dashboard-user-session-proposals-list.png)

![User submissions list](../screenshots/dashboard-user-submissions-list.png)

To submit, these requirements must be met:

- Event must be published.
- CFS must be enabled.
- CFS window must be open.
- Proposal must be eligible for submission.
- Duplicate submission of the same proposal to the same event is blocked.
- Labels must belong to that event's label set.

Response loop behavior:

- `Information requested` asks speaker for changes before re-review.
- `Resubmit` is used after requested changes are addressed.
- `Withdrawn` is speaker-initiated and typically ends active review.

Every review-side change that should reach the speaker is sent as a submission update message.

For submitter-side perspective, see [User Dashboard Guide](user-dashboard.md).

## Automatic Meeting Creation

Automatic meetings are configured in `Date and Venue -> Online event details`.
You can either use your own manual meeting link or let OCG create/manage a meeting automatically.

How automatic mode works:

- Choose `Create meeting automatically`.
- Select provider (currently `Zoom`).
- Optionally add host emails for coordination.
- Save the event.
- Publish the event to trigger meeting creation.
- Wait for sync; join link/password appear once ready.
- Meetings are automatically ended when the configured end time is reached.

Requirements for automatic mode:

- Event type is `virtual` or `hybrid`.
- Start and end are set, with end after start.
- Duration is within provider limits (5 to 720 minutes).
- Event capacity is set.
- Capacity does not exceed configured provider participant limit.
- Manual meeting links are not used at the same time.

Important limitations and behavior:

- In-person events cannot use automatic meetings.
- Due to current technical limitations, host controls are not available in
  automatically created Zoom meetings.
- Switching automatic to manual can remove auto-created meeting details.
- Switching manual to automatic can replace existing manual links.
- Schedule or type changes can disable automatic mode if constraints are no longer met.
- If sync fails, meeting errors surface in the editor until resolved.
- In deployments without automatic-meeting support, only manual meeting URL fields are available.

## Publish, Unpublish, Cancel, Delete

These actions serve different intents:

- `Publish`: make event publicly available.
- `Unpublish`: hide event without canceling it.
- `Cancel`: mark event as not proceeding.
- `Delete`: permanently remove from normal operations.

Message behavior:

- `Publish` on a future unpublished event can notify group members/team members and listed
  speakers.
- `Cancel` on a future published event notifies attendees and speakers.
- Rescheduling a future published event can notify attendees and speakers when the start or end
  time changes by at least 15 minutes.
- `Unpublish` and `Delete` do not send broad attendee updates in this flow.

Automatic-meeting lifecycle in these actions:

- `Publish` triggers creation/sync for configured automatic meetings (event and session meetings).
- `Unpublish`, `Cancel`, and `Delete` trigger removal/sync for configured automatic meetings.

Use the least destructive action that matches your operational goal.

## Public Event Result

The public event page is the delivery surface of all organizer decisions: RSVP controls, logistics,
CFS visibility, and final agenda experience. You can reach it through [`Explore`](/explore ':ignore').

For attendee/member perspective, see [Public Site Guide](public-site.md).

![Public event page](../screenshots/event-page.png)

## Event-Day Checklist

1. Confirm attendee table loads in the `Attendees` tab.
2. Open QR flow and validate the check-in URL.
3. Test one manual check-in path.
4. Prepare attendee email template for urgent updates.
5. Re-verify schedule and meeting links before start.
