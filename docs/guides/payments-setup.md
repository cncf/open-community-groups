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

In practice, this setup usually involves three people: a group administrator
who wants to enable paid events for the group, a platform administrator who
manages the Stripe Connect platform for that OCG deployment, and the fiscal
sponsor's authorized representative who completes Stripe onboarding and tax
setup.

**Sections:**

- [Payments Setup Guide](#payments-setup-guide)
  - [What You Need Before You Start](#what-you-need-before-you-start)
  - [How The Setup Flow Works](#how-the-setup-flow-works)
  - [If You Are The Platform Administrator](#if-you-are-the-platform-administrator)
  - [Step 1: Create the Connected Account](#step-1-create-the-connected-account)
  - [Step 2: Hand Off Setup to the Fiscal Sponsor](#step-2-hand-off-setup-to-the-fiscal-sponsor)
  - [Step 3: Complete Fiscal Sponsor Onboarding](#step-3-complete-fiscal-sponsor-onboarding)
  - [Step 4: Confirm That the Account Is Onboarded](#step-4-confirm-that-the-account-is-onboarded)
  - [Step 5: Configure Tax for the Fiscal Sponsor](#step-5-configure-tax-for-the-fiscal-sponsor)
  - [Step 6: Copy the Stripe Account ID](#step-6-copy-the-stripe-account-id)
  - [Step 7: Save the Fiscal Sponsor in OCG](#step-7-save-the-fiscal-sponsor-in-ocg)
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
- The fiscal sponsor has agreed to sell the tickets, handle registrations,
  filing and remittance, pay provider fees, and monitor refunds, disputes, and
  negative balances.

!> OCG expects a Stripe connected account ID.
The value saved in group settings should look like `acct_...`.

## How The Setup Flow Works

The setup usually happens in four parts:

1. The group identifies a fiscal sponsor or steward that agrees to be the
   seller and tax filer.
2. A platform administrator creates or opens that entity's
   application-controlled, Standard-like Stripe connected account and checks
   direct-charge and tax readiness (Steps 1, 2, and 4).
3. The sponsor completes onboarding, business/invoice details, tax
   registrations, and payout setup (Steps 3 and 5).
4. The group saves the sponsor's legal name and connected account ID in OCG
   group settings (Steps 6 and 7).

Only the final save is completed in the OCG UI. The connected account creation
and Stripe onboarding steps happen in Stripe, outside OCG.

## If You Are The Platform Administrator

This section is for the person who manages the Stripe Connect platform used by
the OCG deployment. You need administrator access to the Stripe Dashboard for
that platform account.

When a group asks to enable paid events, the platform administrator creates
the connected account in Stripe and picks the configuration OCG requires
(Steps 1 and 2); the fiscal sponsor then follows the Stripe onboarding link
and provides its own legal, identity, tax, and payout details (Steps 3 to 5).

| Stripe terminology | Meaning in this guide |
| --- | --- |
| Platform account | The Stripe account with Connect enabled used by the OCG deployment. |
| Connected account | The Stripe account created for the fiscal sponsor and connected to the platform account. |
| Fiscal sponsor | The legal entity that sells the tickets and owns the connected account. |

OCG only supports connected accounts with a Standard-like controller
configuration:

- The OCG Stripe platform controls the account relationship.
- The connected account pays Stripe fees.
- Stripe collects onboarding and verification requirements.
- Stripe is liable if the connected account cannot repay a payment-related
  negative balance.
- The fiscal sponsor has access to the full Stripe Dashboard.

Once the sponsor finishes onboarding, confirm that charges are enabled,
details are submitted, invoice business details are correct, the sponsor can
use the Stripe Dashboard, and the account keeps the configuration above. For
automatic tax, confirm Stripe Tax is active, including the head-office address
and registrations applicable to the event locations. If events use manual tax,
the sponsor creates and maintains those Tax Rate definitions in its connected
Stripe account.

## Step 1: Create the Connected Account

OCG requires a Stripe connected account that belongs to the Stripe Connect
platform used by this OCG deployment and is application-controlled by that
platform.

The connected account must belong to the fiscal sponsor's legal entity. Do not
create it under the platform's own identity or reuse an account that belongs
to an unrelated seller. If the same fiscal sponsor supports another group on
the same Stripe platform, reuse its compatible account; do not share one
account between unrelated legal sellers.

If the sponsor already has a compatible connected account, open it in
`Connect` -> `Connected accounts`, confirm it keeps the required
configuration, and continue with
[Step 2](#step-2-hand-off-setup-to-the-fiscal-sponsor). Otherwise, create the
account:

1. Sign in to the [Stripe Dashboard](https://dashboard.stripe.com/).
2. Select the Stripe Connect platform account used by the OCG deployment.
3. Open `Connect` -> `Connected accounts` and select `Create`.
4. On the `What would you like this account to do?` screen:
   - Select `Accept payments from their own customers`, Stripe's merchant
     configuration, and nothing else.
   - Leave `Receive transfers to their Stripe balance` unselected: OCG creates
     direct charges for the fiscal sponsor and does not use transfers or the
     recipient configuration.
5. On the `Edit account properties` screen, set every property to its required
   value. The `Stripe` Dashboard access option gives the fiscal sponsor the
   full Stripe Dashboard; do not pick `Express` or `None`.

   | Property | Required value |
   | --- | --- |
   | Who pays Stripe fees | This connected account |
   | Use legacy fee type | Leave unselected |
   | Negative balance liability | Stripe |
   | Dashboard access | Stripe |
   | Requirement collection | Stripe |

6. On the `Create account` review screen, check the capabilities, account
   properties, and legal details:
   - Under `All capabilities requested`, confirm that `Card payments` is
     listed: OCG currently creates card-only Stripe Checkout sessions.
   - Make sure `Country` and `Business type` match the fiscal sponsor's legal
     registration. Pick `Individual` only if the sponsor legally operates as
     an individual; for a company, nonprofit, or other legal entity, pick the
     matching Stripe business type.
7. When everything looks right, select `Create`.

!> OCG verifies that the account is ready to accept charges and that it keeps
the required account properties above. Accounts that deviate from that
configuration fail the fiscal-sponsor readiness check.

## Step 2: Hand Off Setup to the Fiscal Sponsor

After creating the account, Stripe shows an onboarding link that collects the
account's remaining required information.

1. Copy the onboarding link.
2. Send it securely to an authorized representative of the fiscal sponsor.
3. Ask them to open the link and complete the requested information.

The link is single-use and expires after a limited time. If it expires before
the sponsor finishes, generate a new one from the connected account page. Do
not publish the link or send it to anyone who is not authorized to act on the
sponsor's behalf.

?> Creating the account does not make it payment-ready. The sponsor still has
to finish Stripe onboarding and clear all outstanding requirements before OCG
can use the account for paid events.

## Step 3: Complete Fiscal Sponsor Onboarding

From here on, the fiscal sponsor's authorized representative works through the
onboarding flow. The platform administrator should not fill in this
information on the sponsor's behalf.

Using the onboarding link, the sponsor:

1. Provides the business and contact information Stripe requests.
2. Completes the required identity and business-verification checks.
3. Adds the bank account or debit card that will receive payouts.
4. Reviews and submits the information to Stripe.
5. Resolves any follow-up requirements Stripe raises during its review.

Which fields appear depends on the sponsor's country and business type. All of
the information must belong to the legal entity selling the tickets.

Beyond onboarding, the sponsor's administrator keeps the account healthy over
time by:

- Maintaining invoice branding and legal business details.
- Maintaining tax registrations and reviewing Stripe Tax reports.
- Monitoring refunds, disputes, negative balances, and Stripe notifications.

### Add an Account for Payouts

Stripe recommends collecting payout account details during connected-account
onboarding (see
[Manage payout accounts for connected accounts](https://docs.stripe.com/connect/payouts-bank-accounts?bank-account-collection-method=manual-entry)).
On the `Bank details` screen, the sponsor selects `Add an account for payouts`
and enters the bank details Stripe asks for. Stripe derives the required
fields from the account's country and currency: an IBAN in some countries,
local account and routing numbers in others.

The payout account must belong to, or be legally controlled by, the fiscal
sponsor, and it is where the proceeds from paid tickets will arrive. The
sponsor enters these details directly in Stripe; they are never added to OCG.

### Add Public Details for Customers

On the `Add public details for customers` screen, the sponsor enters the
public business name and support contact information attendees may see on
payment statements, invoices, and receipts. Accurate, recognizable details
help attendees identify the seller and understand the charge.

These details must identify the fiscal sponsor as the legal seller, not the
OCG platform, unless the platform itself is the fiscal sponsor for this
account.

## Step 4: Confirm That the Account Is Onboarded

Stripe shows `Account onboarded` once the sponsor has submitted everything the
onboarding flow asked for. The sponsor can close the flow at that point.

The platform administrator should then open the connected account in the
Stripe Dashboard and check that no onboarding or verification actions remain.
If Stripe shows outstanding requirements, finish those first: an incomplete
account can delay payouts or block charges.

?> Account onboarded only confirms the onboarding flow itself. Payment,
payout, and invoice readiness still need to be verified before the account is
used for paid events, along with Stripe Tax readiness when events use
automatic tax.

## Step 5: Configure Tax for the Fiscal Sponsor

OCG events can collect tax automatically through Stripe Tax, with manual Tax
Rates defined in the sponsor's connected account, or not at all.

Tax is configured inside the connected account, not the OCG platform account,
because the fiscal sponsor is the legal seller and owns the direct charges,
invoices, and Tax records for paid tickets. The sponsor's administrator
performs this configuration; the platform administrator only confirms
afterwards that the expected tax setup is in place.

### Automatic Tax with Stripe Tax

1. From the connected account's Stripe Dashboard, open `Tax`.
2. On the `Overview` tab, Stripe shows how many steps remain to start
   collecting tax automatically. Select `View all steps`, or the `Next up`
   shortcut, and complete every remaining step, including the head-office
   address and the tax registrations that reflect where the fiscal sponsor is
   registered to collect tax and the jurisdictions applicable to its event
   locations. After adding the registrations, the administrator can open the
   `Locations` tab to verify that tax is properly set up for each expected
   country or jurisdiction and to review the potential tax obligations Stripe
   detects from the account's transactions.
3. Repeat until the `Overview` tab no longer reports remaining setup steps and
   Stripe Tax is active.

Stripe may offer pay-as-you-go and monthly pricing. Tax activity is billed to
the connected account, so the sponsor should review the available plans and
understand the applicable charges.

Stripe Tax only calculates and collects tax in the locations where the
connected account has an active registration. OCG checks that the connected
account's Stripe Tax settings are active and that an active registration covers
the event venue whenever automatic-tax readiness is required. OCG does not
restrict venue countries, but Stripe Tax must support the venue location;
unsupported locations fail readiness and require Manual Stripe Tax Rates.
Registrations match at country level, with an exact state match
for United States venues. Canadian country-wide registrations cover every
province; a province-specific registration must match the venue province. These
readiness checks catch missing setup, but the sponsor and platform administrator
must still verify the calculated tax result for each venue.

Tax for ticket sales is in public preview and requires API version
`2026-03-25.preview` or later. The OCG deployment configuration pins the
version used for these calls; prior Stripe approval is not part of the current
setup. Contact Stripe Support only if a qualifying version returns an access
or feature-disabled error.

### Manual Tax Rates

For manual tax, the sponsor owns the Tax Rate definitions in its connected
Stripe account. Create active rates with the intended display name,
jurisdiction, percentage, and inclusive or exclusive behavior. Event organizers
then select the compatible rates in each event's `Tickets` tab. OCG does not
copy or maintain the rate metadata. Every selected rate must declare the event
venue country. When the venue has a state or province code, a rate that
declares one must also match that venue subdivision.

### Stripe-Side Readiness

At the end of this step, the connected account must be ready to create direct
charges and own Checkout, Customer, invoice, refund, dispute, Tax, and credit
note objects. Stripe Tax calculation and reports do not make Stripe or OCG the
filer; the sponsor still files and remits where required.

## Step 6: Copy the Stripe Account ID

After the connected account exists, copy its Stripe account ID. Make sure you
copy the connected account ID itself, not a publishable key, secret key,
payment link, or customer ID. Stripe documents connected account IDs as values
that usually start with `acct_`:
[Account API reference](https://docs.stripe.com/api/accounts/object).

If you are working from the Stripe dashboard, use the account details for the
connected account created for the group in
[Step 1](#step-1-create-the-connected-account).

## Step 7: Save the Fiscal Sponsor in OCG

Once you have the sponsor's legal name and `acct_...` value:

1. Open [Group Dashboard](/guides/group-dashboard.md).
2. Go to `Settings`.
3. Find the `Fiscal Sponsor` section.
4. Enter the legal seller name shown to attendees into `Fiscal Sponsor Legal
   Name`.
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
virtual access, but a virtual-only ticket must remain free. In the event's
`Tickets` tab, choose automatic Stripe Tax, one or more manual Tax Rates from
the sponsor account, or no tax collection. Automatic and manual modes also
choose inclusive or exclusive display. OCG revalidates manual selections against
the connected account and venue jurisdiction when the event is saved,
published, and checked out. Automatic-tax readiness likewise checks the active
registration for the venue when paid setup is saved or revalidated.

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

- [Account API reference](https://docs.stripe.com/api/accounts/object)
- [Account controller properties](https://docs.stripe.com/connect/migrate-to-controller-properties)
- [Create a connected account](https://docs.stripe.com/connect/saas/tasks/create)
- [Create direct charges](https://docs.stripe.com/connect/direct-charges)
- [Disputes on Connect platforms](https://docs.stripe.com/connect/disputes)
- [Manage connected accounts with the Dashboard](https://docs.stripe.com/connect/dashboard)
- [Manage individual accounts](https://docs.stripe.com/connect/dashboard/managing-individual-accounts)
- [Manage payout accounts for connected accounts](https://docs.stripe.com/connect/payouts-bank-accounts?bank-account-collection-method=manual-entry)
- [Onboard your connected account](https://docs.stripe.com/connect/saas/tasks/onboard)
- [Product release phases](https://docs.stripe.com/release-phases)
- [Tax for ticket sales](https://docs.stripe.com/tax/tax-for-tickets/integration-guide)
- [Tax registrations](https://docs.stripe.com/tax/registrations-api)
- [Use manual Tax Rates](https://docs.stripe.com/payments/checkout/use-manual-tax-rates)
