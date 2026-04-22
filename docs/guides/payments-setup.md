<!-- markdownlint-disable MD013 -->

# Payments Setup Guide

Use this guide when your group wants to run paid events in OCG.

In OCG, a group is ready for paid events only when both of these are true:

1. The OCG deployment has Stripe payments enabled.
2. The group has a Stripe connected account saved in
   [Group Dashboard -> Settings](/guides/group-dashboard.md#payments-group-recipient-setup).

OCG does not create or onboard Stripe accounts from the group dashboard. The
group dashboard only stores the Stripe connected account identifier that should
receive payouts for that group's paid events.

In practice, this setup usually involves two people:

- A group administrator who wants to enable paid events for the group.
- A platform administrator who manages the Stripe Connect platform for that OCG
  deployment.

**Sections:**

- [Payments Setup Guide](#payments-setup-guide)
  - [What You Need Before You Start](#what-you-need-before-you-start)
  - [How The Setup Flow Works](#how-the-setup-flow-works)
  - [If You Are The Platform Administrator](#if-you-are-the-platform-administrator)
  - [Step 1: Create or Open the Stripe Connected Account](#step-1-create-or-open-the-stripe-connected-account)
  - [Step 2: Complete Stripe Onboarding and Payout Details](#step-2-complete-stripe-onboarding-and-payout-details)
  - [Step 3: Copy the Stripe Account ID](#step-3-copy-the-stripe-account-id)
  - [Step 4: Save the Recipient in OCG](#step-4-save-the-recipient-in-ocg)
  - [What Happens After Setup](#what-happens-after-setup)
  - [Official Stripe References](#official-stripe-references)

## What You Need Before You Start

Before you configure payments for a group, confirm these points:

- The OCG deployment has Stripe payments enabled. If the payments section does
  not appear in group settings, ask your platform administrator to verify the
  server-side Stripe setup.
- You have permission to edit the group in
  [Group Dashboard -> Settings](/guides/group-dashboard.md#settings-group-identity).

!> OCG expects a Stripe connected account ID.
The value saved in group settings should look like `acct_...`.

## How The Setup Flow Works

The setup usually happens in three parts:

1. A group administrator asks the platform administrator to create a Stripe
   connected account for the group on the deployment's Stripe Connect
   platform.
2. The group administrator completes Stripe onboarding and payout details for
   that connected account.
3. The group administrator saves the connected account ID in OCG group
   settings.

Only the last step is completed in the OCG UI. The connected account creation
and Stripe onboarding steps happen in Stripe, outside OCG.

## If You Are The Platform Administrator

This section is for the person who manages the Stripe Connect platform used by
the OCG deployment.

When a group asks to enable paid events, the Stripe-side work is usually:

1. Open the Stripe Dashboard for the OCG deployment's platform account.
2. Go to `Connected accounts`.
3. Create a new connected account for the group.
4. Choose the connected-account access model you want the group to have in
   Stripe.
5. Give the group administrator access to that connected account so they can
   complete onboarding and payout setup.

Useful Stripe references for this step:

- [Manage connected accounts with the Dashboard](https://docs.stripe.com/connect/dashboard)
- [Create a connected account](https://docs.stripe.com/connect/saas/tasks/create)
- [Onboard your connected account](https://docs.stripe.com/connect/saas/tasks/onboard)
- [Express Dashboard](https://docs.stripe.com/connect/express-dashboard)

## Step 1: Create or Open the Stripe Connected Account

OCG currently requires an existing Stripe connected account that belongs to the
Stripe Connect platform used by this OCG deployment.

If the group does not already have one, ask your platform administrator to
create the connected account that should receive funds for the group.

Once that connected account exists, the group administrator can be given access
to that connected account in Stripe to finish the remaining setup there.

Recommended Stripe starting points:

- Use Stripe's Connected Accounts dashboard documentation:
  [Manage individual accounts](https://docs.stripe.com/connect/dashboard/managing-individual-accounts).
- If the connected account still needs onboarding, follow Stripe's guide:
  [Onboard your connected account](https://docs.stripe.com/connect/saas/tasks/onboard).

If your organization already has a connected account on the same Stripe
platform, you can usually reuse that existing account instead of creating a new
one for the group.

## Step 2: Complete Stripe Onboarding and Payout Details

Before selling paid tickets, finish the Stripe onboarding steps required for
the connected account.

Typical Stripe tasks include:

- Completing the business or individual profile Stripe asks for.
- Satisfying any identity or tax requirements Stripe marks as due.
- Adding the bank account or debit card that should receive payouts.

This step is completed by the group administrator once they have access to that
connected account in Stripe.

At the end of this step, the Stripe connected account should be ready to
receive payouts for the group.

Stripe recommends collecting payout account details during connected-account
onboarding. See:
[Manage payout accounts for connected accounts](https://docs.stripe.com/connect/payouts-bank-accounts?bank-account-collection-method=manual-entry).

?> If Stripe shows outstanding requirements for the connected account, finish
those first. An incomplete account can delay payouts or block charges.

## Step 3: Copy the Stripe Account ID

After the connected account exists, copy its Stripe account ID.

What to look for:

- The identifier is the connected account ID, not a publishable key, secret
  key, payment link, or customer ID.
- Stripe documents connected account IDs as values that usually start with
  `acct_`: [Connected Accounts API reference](https://docs.stripe.com/api/connected_accounts).

If you are working from the Stripe dashboard, use the account details for the
connected account created for the group in the previous step.

## Step 4: Save the Recipient in OCG

Once you have the `acct_...` value:

1. Open [Group Dashboard](/guides/group-dashboard.md).
2. Go to `Settings`.
3. Find the `Payments` section.
4. Paste the Stripe connected account ID into `Stripe Recipient`.
5. Save the group settings.

That setting applies at the group level. Paid events created for that group use
the saved Stripe recipient.

If you leave the field blank, the group can still run free RSVP events, but it
cannot use ticketed events.

## What Happens After Setup

After the recipient is saved:

- Group administrators can create ticketed events for the group.
- Paid attendees are sent to Stripe Checkout during purchase.
- Refund requests stay managed in OCG by group administrators.
- The group can continue managing its connected account details in Stripe when
  needed.

For the rest of the paid-event flow, continue to
[Event Operations](event-operations.md#paid-events-tickets-discounts-refunds).

## Official Stripe References

- [Manage individual accounts](https://docs.stripe.com/connect/dashboard/managing-individual-accounts)
- [Onboard your connected account](https://docs.stripe.com/connect/saas/tasks/onboard)
- [Manage payout accounts for connected accounts](https://docs.stripe.com/connect/payouts-bank-accounts?bank-account-collection-method=manual-entry)
- [Connected Accounts API reference](https://docs.stripe.com/api/connected_accounts)
