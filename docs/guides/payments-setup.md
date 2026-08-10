<!-- markdownlint-disable MD013 -->

# Payments Setup Guide

Use this guide when your group wants to configure ticket prices that may require
payment in OCG. Events with only free ticket types do not require Stripe.

In OCG, a group is ready for paid events only when both of these are true:

1. The OCG deployment has Stripe payments enabled.
2. The group has selected a fiscal sponsor or steward through a compatible
   Stripe connected account saved in
   [Group Dashboard -> Settings](/guides/group-dashboard.md#payments-fiscal-sponsor-setup).

OCG does not create or onboard Stripe accounts from the group dashboard. The
group dashboard stores the connected-account identifier for the legal entity
that acts as seller, invoice issuer, and indirect-tax filer. One fiscal sponsor
may support multiple groups.

Event enrollment remains available without these prerequisites. An event is
paid-capable when any active or inactive ticket type has a positive current or
future price window, including invitation-only tiers.

In practice, this setup usually involves two people: a group administrator
who wants to enable paid events for the group, and a platform administrator
who manages the Stripe Connect platform for that OCG deployment.

**Sections:**

- [Payments Setup Guide](#payments-setup-guide)
  - [What You Need Before You Start](#what-you-need-before-you-start)
  - [How The Setup Flow Works](#how-the-setup-flow-works)
  - [If You Are The Platform Administrator](#if-you-are-the-platform-administrator)
  - [Step 1: Create or Open the Stripe Connected Account](#step-1-create-or-open-the-stripe-connected-account)
  - [Step 2: Complete Stripe Onboarding and Payout Details](#step-2-complete-stripe-onboarding-and-payout-details)
  - [Step 3: Copy the Stripe Account ID](#step-3-copy-the-stripe-account-id)
  - [Step 4: Save the Fiscal Sponsor in OCG](#step-4-save-the-fiscal-sponsor-in-ocg)
  - [What Happens After Setup](#what-happens-after-setup)
  - [Official Stripe References](#official-stripe-references)

## What You Need Before You Start

Before you configure payments for a group, confirm these points:

- The OCG deployment has Stripe payments enabled. If the payments section does
  not appear in group settings, paid ticketing is unavailable, but free-only
  events with free ticket types still work.
- You have permission to edit the group in
  [Group Dashboard -> Settings](/guides/group-dashboard.md#settings-group-identity).
- Your event is in-person or hybrid and has a complete physical venue. Virtual
  events can use only free tickets. Every paid hybrid ticket must include
  physical admission; it may also include virtual access, but cannot be
  virtual-only.
- The fiscal sponsor has agreed to sell the tickets and handle registrations,
  filing, remittance, provider fees, refunds, disputes, and negative balances.

!> OCG expects a Stripe connected account ID.
The value saved in group settings should look like `acct_...`.

## How The Setup Flow Works

The setup usually happens in three parts:

1. The group identifies a fiscal sponsor or steward that agrees to be the
   seller and tax filer.
2. A platform administrator creates or connects that entity's Standard-like
   Stripe account and checks direct-charge and tax readiness.
3. The sponsor completes onboarding, business/invoice details, tax
   registrations, and payout setup.
4. The group saves the sponsor's legal name and connected account ID in OCG
   group settings.

Only the last step is completed in the OCG UI. The connected account creation
and Stripe onboarding steps happen in Stripe, outside OCG.

## If You Are The Platform Administrator

This section is for the person who manages the Stripe Connect platform used by
the OCG deployment.

When a group asks to enable paid events, the Stripe-side work is usually:

1. Open the Stripe Dashboard for the OCG deployment's platform account.
2. Go to `Connected accounts`.
3. Create or open the connected account belonging to the fiscal sponsor.
4. Confirm it uses Standard-like responsibility: the account controls itself,
   pays Stripe fees, and is responsible for payment losses.
5. Confirm charges are enabled, details are submitted, invoice business
   details are correct, and the sponsor can use the Stripe Dashboard.
6. Confirm Stripe Tax is active for automatic tax, including required
   registrations and the ticket-tax preview. If automatic tax is unavailable,
   record only fixed venue rates explicitly supplied or approved by the
   sponsor.

Useful Stripe references for this step:

- [Manage connected accounts with the Dashboard](https://docs.stripe.com/connect/dashboard)
- [Create a connected account](https://docs.stripe.com/connect/saas/tasks/create)
- [Onboard your connected account](https://docs.stripe.com/connect/saas/tasks/onboard)
- [Stripe Dashboard access](https://docs.stripe.com/connect/dashboard)

## Step 1: Create or Open the Stripe Connected Account

OCG currently requires an existing Stripe connected account that belongs to the
Stripe Connect platform used by this OCG deployment.

If the sponsor does not already have one, ask your platform administrator to
create the connected account owned by that legal entity.

Once that connected account exists, the sponsor's authorized administrator
finishes the remaining setup in Stripe.

Recommended Stripe starting points:

- Use Stripe's Connected Accounts dashboard documentation:
  [Manage individual accounts](https://docs.stripe.com/connect/dashboard/managing-individual-accounts).
- If the connected account still needs onboarding, follow Stripe's guide:
  [Onboard your connected account](https://docs.stripe.com/connect/saas/tasks/onboard).

If the same fiscal sponsor supports another group on the same Stripe platform,
reuse its compatible account. Do not share one account between unrelated legal
sellers.

## Step 2: Complete Stripe Onboarding and Payout Details

Before selling paid tickets, finish the Stripe onboarding steps required for
the connected account.

Typical sponsor tasks include:

- Completing the business or individual profile Stripe asks for.
- Satisfying any identity or tax requirements Stripe marks as due.
- Adding the bank account or debit card that should receive payouts.
- Maintaining invoice branding and legal business details.
- Maintaining tax registrations and reviewing Stripe Tax reports.
- Monitoring refunds, disputes, negative balances, and Stripe notifications.

This step is completed by the fiscal sponsor's authorized administrator.

At the end of this step, the connected account must be ready to create direct
charges and own Checkout, Customer, invoice, refund, dispute, Tax, and credit
note objects. Stripe Tax calculation and reports do not make Stripe or OCG the
filer; the sponsor still files and remits where required.

Stripe recommends collecting payout account details during connected-account
onboarding. See:
[Manage payout accounts for connected accounts](https://docs.stripe.com/connect/payouts-bank-accounts?bank-account-collection-method=manual-entry).

?> If Stripe shows outstanding requirements for the connected account, finish
those first. An incomplete account can delay payouts or block charges.

## Step 3: Copy the Stripe Account ID

After the connected account exists, copy its Stripe account ID. Make sure you
copy the connected account ID itself, not a publishable key, secret key,
payment link, or customer ID. Stripe documents connected account IDs as values
that usually start with `acct_`:
[Connected Accounts API reference](https://docs.stripe.com/api/connected_accounts).

If you are working from the Stripe dashboard, use the account details for the
connected account created for the group in the previous step.

## Step 4: Save the Fiscal Sponsor in OCG

Once you have the sponsor's legal name and `acct_...` value:

1. Open [Group Dashboard](/guides/group-dashboard.md).
2. Go to `Settings`.
3. Find the `Payments` section.
4. Enter the legal seller name shown to attendees.
5. Paste the Stripe connected account ID into `Fiscal Sponsor Stripe Account`.
6. Save the group settings.

That setting applies at the group level. New purchases snapshot the sponsor so
later group-setting changes cannot redirect refunds or financial documents.

If you leave both fields blank, the group can run events with free ticket types.
Positive ticket prices cannot be configured or published.

## What Happens After Setup

Once the sponsor is saved, group administrators can configure positive prices
only for eligible in-person or hybrid events with a complete physical venue.
Every paid hybrid ticket includes physical admission. It may also include
virtual access, but a virtual-only ticket must remain free. Choose inclusive or
exclusive tax and use automatic tax whenever it is ready. A manual fallback
must contain current, positive fixed rates approved by the sponsor for that
exact venue, currency, and tax behavior; OCG never guesses a rate.

A positive final price uses sponsor-owned Stripe Checkout with required billing
address, business tax-ID collection, and post-payment invoicing. An
intrinsically free or discounted-to-zero claim completes inside OCG without an
invoice. Refund requests remain managed in OCG, but customer refunds are full
only and funded from the sponsor account. OCG does not subscribe to or process
dispute events; the sponsor monitors and handles them entirely in Stripe,
including any application-fee, tax, or document action.

For the rest of the paid-event flow, continue to
[Event Operations](event-operations.md#tickets-discounts-and-refunds).

## Official Stripe References

- [Manage individual accounts](https://docs.stripe.com/connect/dashboard/managing-individual-accounts)
- [Onboard your connected account](https://docs.stripe.com/connect/saas/tasks/onboard)
- [Manage payout accounts for connected accounts](https://docs.stripe.com/connect/payouts-bank-accounts?bank-account-collection-method=manual-entry)
- [Connected Accounts API reference](https://docs.stripe.com/api/connected_accounts)
- [Create direct charges](https://docs.stripe.com/connect/direct-charges)
- [Tax for ticket sales](https://docs.stripe.com/tax/tax-for-tickets/integration-guide)
- [Use manual Tax Rates](https://docs.stripe.com/payments/checkout/use-manual-tax-rates)
- [Disputes on Connect platforms](https://docs.stripe.com/connect/disputes)
