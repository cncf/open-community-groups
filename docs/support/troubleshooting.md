<!-- markdownlint-disable MD013 -->

# Troubleshooting

This page helps you diagnose issues quickly by symptom.

## I Cannot Access a Dashboard

Check:

1. You are logged in.
2. You accepted the related invitation in
   [`User Dashboard -> Invitations`](/dashboard/user?tab=invitations ':ignore').
3. You selected the required context:
   - [Community dashboard](/dashboard/community ':ignore'): selected community.
   - [Group dashboard](/dashboard/group ':ignore'): selected community and group.

If actions still fail, re-select the community/group from dashboard selectors and refresh.

![Group team area](../screenshots/dashboard-user-invitations.png)

## Controls Are Disabled in Dashboard Tabs

Disabled controls usually indicate role-based authorization, not a UI bug.

Examples:

- Community `viewer` cannot modify settings/taxonomy/team/groups.
- Community `groups-manager` cannot modify community settings/taxonomy/team.
- Group `events-manager` can manage events but cannot manage members/settings/sponsors/team.
- Group `viewer` is read-only.

If you need broader access, request a higher role from a team admin.

## Join Group or Attend Event Buttons Do Not Work

Check:

1. You are logged in.
2. The group/event is active and available.
3. Your session is up to date (refresh page).

For events:

- Capacity limits can block new attendance.
- Canceled events disable normal participation.

## CFS Submit Button Is Disabled

Check:

1. CFS is enabled for the event.
2. CFS time window is currently open.
3. You are logged in.
4. You have at least one eligible session proposal.

In modal:

- Proposal options already submitted to the same event are disabled.

## I Cannot Resubmit or Withdraw a Submission

Submission actions depend on status:

- `Resubmit` is available for `Information requested`.
- `Withdraw` is available only while the submission is still active in review.
- After a final outcome (such as approved/linked), withdraw is no longer available.

Confirm current status in [`User Dashboard -> Submissions`](/dashboard/user?tab=submissions ':ignore').

![User submissions list](../screenshots/dashboard-user-submissions-list.png)

## Event Cannot Be Published

Check event editor completeness:

1. Required details are filled (name, type, category, description).
2. Date/time is valid (end on/after start).
3. Meeting constraints are satisfied when automatic meeting is requested.
4. CFS rules are valid if CFS is enabled.

## Check-In Is Unavailable

Check:

1. You RSVP'd with this account.
2. Event is published and not canceled.
3. Check-in window is open:
   - Opens 2 hours before start.
   - Closes end of event day (or final day for multi-day events).

## Team Member Remove Action Is Disabled

For community/group team tables:

- You cannot remove or demote the final accepted `admin`.

Add another accepted team member first, then retry.

![Dashboard group members list](../screenshots/dashboard-group-members-list.png)

## Analytics Looks Outdated

Analytics is cached and can lag by a few minutes.

Retry:

1. Refresh the page.
2. Wait briefly and refresh again.

## Email Send Is Disabled

For group members or event attendees:

- Send actions are disabled when recipient count is zero.

Also verify required fields:

- Title
- Body (plain text)

## More Help

If you do not see your issue here, check the
[Frequently Asked Questions](faq.md).
