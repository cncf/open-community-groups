<!-- markdownlint-disable MD013 -->

# Troubleshooting

This page helps you diagnose issues quickly by symptom. Find the situation that matches what you
are seeing and work through the checks in order.

## I Cannot Access a Dashboard

Check that:

1. You are logged in.
2. You accepted the related invitation in
   [User Dashboard -> Invitations](/dashboard/user?tab=invitations ':ignore').
3. You selected the required context:
   - [Community dashboard](/dashboard/community ':ignore'): selected community.
   - [Group dashboard](/dashboard/group ':ignore'): selected community and group.

If actions still fail, re-select the community/group from dashboard selectors and refresh.

![Group team area](../screenshots/dashboard-user-invitations.png)

## Controls Are Disabled in Dashboard Tabs

Disabled controls usually indicate role-based authorization, not a UI bug. Some examples:

- Community `viewer` cannot modify settings/taxonomy/team/groups.
- Community `groups-manager` cannot modify community settings/taxonomy/team.
- Group `events-manager` can manage events but cannot manage members/settings/sponsors/team.
- Group `check-in-manager` can scan and manually check in attendees but cannot edit events.
- Group `viewer` is read-only.

If you need broader access, request a higher role from a team admin.

## Join Group or Attend Event Buttons Do Not Work

Check that:

1. You are logged in.
2. The group/event is active and available.
3. Your session is up to date (refresh page).

For events, also keep in mind that capacity limits can block new attendance and that canceled
events disable normal participation.

## LF SSO Email Changes

OCG can recognize returning LF SSO users after their LF email changes when the account has already
been linked through LF SSO. If login reports that the account cannot be safely connected, an
administrator should check whether another OCG account already owns the new email or whether the
user's older account needs to be reconnected.

This reconciliation happens during login. Organizer-created email invitations still resolve by the
email supplied at invitation time: if that email does not match an existing registered account, OCG
creates a pre-registered placeholder. A verified LF SSO login activates that placeholder when the LF
account email still matches the invited email. OCG does not transfer placeholders by LF SSO identity
when the email differs, and ownership conflicts must be reconciled before the user tries again.

## CFS Submit Button Is Disabled

Check that:

1. CFS is enabled for the event.
2. CFS time window is currently open.
3. You are logged in.
4. You have at least one eligible session proposal.

Inside the modal, proposal options already submitted to the same event are disabled.

## I Cannot Resubmit or Withdraw a Submission

Submission actions depend on status. `Resubmit` is available for `Information requested`, while
`Withdraw` is available only while the submission is still active in review. After a final
outcome (such as approved/linked), withdraw is no longer available.

Confirm current status in [User Dashboard -> Submissions](/dashboard/user?tab=submissions ':ignore').

![User submissions list](../screenshots/dashboard-user-submissions-list.png)

## Event Cannot Be Published

Check event editor completeness:

1. Required details are filled (name, type, category, description).
2. Date/time is valid (end on/after start).
3. Registration open and close dates are not after the event start date, and close is after open if a
   registration window is set.
4. Meeting constraints are satisfied when automatic meeting is requested.
5. CFS rules are valid if CFS is enabled.

For every event also verify:

1. The event has at least one ticket type configured. The last tier cannot be
   removed.
2. Every ticket type has a `Public` or `Invitation only` availability value.
3. Each ticket type has at least one complete price window.
4. Free-only ticketing has no event currency or discount codes.
5. Paid-capable ticketing has an event currency, server payment provider, and
   fiscal-sponsor connected account.
6. Any configured discount codes are complete. Discount codes are optional.

## Ticket Claim Is Unavailable or Fails

If getting, requesting, or claiming a ticket is unavailable or does not
complete, check:

1. The selected ticket type is active, currently priced, and public for direct
   enrollment.
2. The ticket type has a price window that is currently in effect.
3. The event registration window is currently open for starting checkout, if one is configured.
   Existing active ticket holds can still complete until the hold expires.
4. The discount code is active, still has remaining uses, and has not reached any total-use
   limit. Remaining uses are reserved by active holds and active purchases, then released again if
   the hold expires or the ticket is refunded.
5. The event has not been canceled.
6. A positive final price has current server payment configuration and a group
   fiscal-sponsor connected account, eligible in-person or hybrid event with a
   complete physical venue, and valid tax setup. A paid hybrid ticket includes
   physical admission and is not virtual-only.
7. An offer claim uses the exact tier assigned to that offer and occurs before
   its deadline.

For invitation-only events, use the assigned offer in
[User Dashboard -> Invitations](/dashboard/user?tab=invitations ':ignore').
Private tier names and prices do not appear on the public event page.

## Check-In Is Unavailable

Check that:

1. You completed a ticket with this account.
2. The event is published, not canceled, and has not ended.
3. You opened [User Dashboard -> Check-In](/dashboard/user?tab=check-in ':ignore') and selected
   the event.

If an organizer's scanner is unavailable, confirm the page uses HTTPS, allow camera permission in
the browser, try another listed camera, and check that no other application is using it. The
organizer can always use the attendee table's manual check-in toggle instead.

## Team Member Remove Action Is Disabled

In community and group team tables, you cannot remove or demote the final accepted `admin`. Add
another accepted team member first, then retry.

![Dashboard group members list](../screenshots/dashboard-group-members-list.png)

## Analytics Looks Outdated

Analytics is cached and can lag by a few minutes. Refresh the page, wait briefly, and refresh
again.

## Email Send Is Disabled

For group members or event attendees, send actions are disabled when the recipient count is
zero. Also verify that the required fields are filled: `Subject` and the plain-text message body.

## More Help

If you do not see your issue here, check the
[Frequently Asked Questions](faq.md).
