<!-- markdownlint-disable MD013 -->

# Frequently Asked Questions

## Is OCG Mobile Friendly?

Public pages are usable on mobile, so you can discover groups and events from your phone. The
dashboards, however, are currently desktop-only.

## Where Do I Submit a Speaker Proposal?

Proposal creation and submission happen in two different places. First create your proposals in
[User Dashboard -> Session proposals](/dashboard/user?tab=session-proposals ':ignore'), then
submit them from each event's public CFS modal. This split lets you reuse the same proposal
across multiple events.

![Session proposals list](../screenshots/dashboard-user-session-proposals-list.png)

## Why Is My Proposal Missing in CFS Modal?

If a proposal you expect to see is not offered in the CFS modal, the likely causes are:

- The proposal is not in a status eligible for submission.
- The proposal was already submitted to this event.
- You are logged in with a different account.

## Can I Undo a Submission?

Yes, within limits. You can withdraw a submission while review is still active. After a final
decision has been made, withdraw is no longer available.

## Can I Check In Without Confirmed Attendance?

No. Check-in is limited to confirmed attendees, so you need a completed ticket
before event-day check-in.

## What Happens If An Event Is Full?

Each sold-out public ticket type has its own waiting list when the organizer
enables waiting lists. A promotion creates a time-limited offer in
[User Dashboard -> Invitations](/dashboard/user?tab=invitations ':ignore').
The offer must be claimed before its deadline.

## Do Free Tickets Need Stripe?

No. Events whose ticket prices are all zero work without server payment configuration, a
group payment recipient, or event currency. Stripe is required only when a
configured or claim-time final price may be positive.

## Why Is Registration Disabled?

Organizers may configure a registration window. Before it opens and after it closes,
starting ticket checkout, invitation requests, waitlist joining, and registration-question answers
are disabled. The event page shows the open or close time when a window is configured.

If you started checkout before registration closed, the active ticket hold can still be completed
until it expires.

Organizer-created offers are an exception. They can be claimed and their
required registration questions answered outside the public registration
window until the offer expires.

## How Do Ticket Offers Work?

Approved ticket requests, organizer invitations, and waiting-list promotions
create offers. The Invitations tab shows the assigned tier,
displayed price, and exact deadline. No charge or attendance exists until the
offer is claimed and any positive checkout completes.

The ticket price is finalized on first claim. An interrupted checkout can be
resumed with the same snapshot or canceled to release the hold. Declining an
offer releases its reserved capacity.

## How Do Refunds Work For Paid Events?

Paid attendees use `Request refund` from the public event page, and organizers review the
request from [Group Dashboard -> Event -> Attendees](/dashboard/group?tab=events ':ignore'). An
organizer can also choose `Cancel attendance and refund` for a confirmed paid attendee to queue a
full refund directly.

A few rules apply:

- Refunds are full refunds only.
- Refund requests are available only before the event starts.
- Organizers can still approve or reject a request later if it was submitted before the start
  time.
- Organizer-initiated paid cancellation keeps attendance active until the refund is confirmed or
  manual recovery is recorded.
- Free ticket attendees can still leave the event normally.

Before payment is complete, attendees can use `Cancel checkout` from the public event page to
release the ticket hold and choose a different ticket or discount code.

Free attendance releases capacity immediately when canceled. Paid capacity
remains allocated while a refund is pending and is released after provider
refund finalization or recorded manual recovery.

## Can I Use Automatic Meeting Creation on In-Person Events?

No. Automatic meeting requests are allowed only for `virtual` and `hybrid` events, since
in-person events have no online meeting to create.

## Are Automatically Created Meetings Ended Automatically?

Yes. Meetings created automatically are also ended automatically when the configured end time is
reached.

## Why Are Host Controls Missing in Automatically Created Zoom Meetings?

Due to some current technical limitations, host controls are not available in automatically
created Zoom meetings at the moment.

## Where Can I See Platform-Wide Growth Trends?

The public [Stats](/stats ':ignore') page shows platform-level growth and trends: groups,
members, events, and attendees over time.

![Stats page](../screenshots/stats-page.png)
