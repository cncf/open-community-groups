<!-- markdownlint-disable MD013 -->

# Stripe Payments Deployment Guide

This document is for OCG operators and deployment maintainers. It is intentionally unlisted
from the public docs navigation because it covers server configuration, Stripe platform setup,
and operational caveats.

## What This Enables

Once this setup is complete:

- OCG can create direct-charge Stripe Checkout sessions for eligible paid
  in-person and hybrid events with complete physical venues.
- OCG can verify platform and connected-account webhook signatures separately.
- Groups can select a fiscal sponsor or steward through its connected account.
- Group administrators can configure paid-capable events and process
  refunds in OCG.
- Attendees receive Stripe invoices and can access invoices and issued credit
  notes from their user dashboard.

Events with only free ticket types work when Stripe is not configured. Enrollment requires
Stripe only when a configured or claim-time final price may be positive.

Deployments that serve groups in countries without Stripe Connect can also enable
[External Payments](#external-payments), which lets allowlisted groups collect
paid tickets outside OCG. That feature is configured separately and does not
require Stripe.

## Stripe Requirements

OCG's payments integration is built around Stripe Connect and Stripe Checkout.

You need:

- A Stripe platform account with Connect enabled.
- Access to the Stripe Dashboard for that platform account.
- A public HTTPS URL for your OCG server.
- A decision about whether this deployment is running in Stripe `test` mode or
  Stripe `live` mode.
- Application-controlled, Standard-like connected accounts where the connected
  account pays Stripe fees, Stripe collects requirements, Stripe assumes
  ultimate liability for payment-related negative balances, and the sponsor has
  full Dashboard access.
- Active Stripe Tax settings, a head-office address, and applicable tax
  registrations for each fiscal sponsor that uses automatic tax.
- A Tax for ticket sales public-preview API version of `2026-03-25.preview` or
  later. Manual-tax events instead select active Tax Rates owned by the fiscal
  sponsor's connected account.

Useful Stripe references:

- [Account API reference](https://docs.stripe.com/api/accounts/object)
- [Account controller properties](https://docs.stripe.com/connect/migrate-to-controller-properties)
- [API keys](https://docs.stripe.com/keys)
- [How Connect works](https://docs.stripe.com/connect/how-connect-works)
- [Platforms and marketplaces with Stripe Connect](https://docs.stripe.com/connect)
- [Product release phases](https://docs.stripe.com/release-phases)
- [Receive Stripe events in your webhook endpoint](https://docs.stripe.com/webhooks)
- [Tax for ticket sales](https://docs.stripe.com/tax/tax-for-tickets/integration-guide)
- [Use a prebuilt Stripe-hosted payment page](https://docs.stripe.com/payments/checkout)

## OCG Configuration

### Helm Values

The Helm chart exposes Stripe configuration in `charts/ocg/values.yaml`:

```yaml
payments:
  enabled: true
  provider: stripe
  mode: test
  connectedWebhookSecret: "whsec_..."
  secretKey: "sk_test_..."
  ticketTaxApiVersion: "2026-07-29.preview"
  webhookSecret: "whsec_..."
  platformFeeBps: 0
```

A few notes about these values:

- Set `enabled: true` to make payments available in OCG.
- Set `provider: stripe` because OCG currently supports one configured payments
  provider at a time and Stripe is the only implemented provider.
- Use `mode: test` with a Stripe test key.
- Use `mode: live` only with a live Stripe key.
- `secretKey`, `webhookSecret`, and `connectedWebhookSecret` are required when
  payments are enabled. The two signing secrets must come from their respective
  Stripe event destinations.
- `ticketTaxApiVersion` is required when payments are enabled and is used for
  automatic ticket tax and credit-note operations. Tax for ticket sales is in
  public preview and requires `2026-03-25.preview` or later. This example pins
  `2026-07-29.preview`; test the complete payment flow before changing it
  because Stripe preview versions can contain breaking changes.
- `platformFeeBps` is optional and defaults to `0` (no platform fee). See
  [Platform Fee](#platform-fee) for its semantics.

### Raw Server Config

If you are not using the Helm chart, the equivalent `server.yml` section is:

```yaml
payments:
  provider: stripe
  mode: test
  connected_webhook_secret: "whsec_..."
  secret_key: "sk_test_..."
  ticket_tax_api_version: "2026-07-29.preview"
  webhook_secret: "whsec_..."
  platform_fee_bps: 0
```

The server validates that both webhook secrets, the API key, and the ticket Tax
API version are non-empty when Stripe payments are configured. Stripe rejects
unsupported API versions when OCG makes a request. Tax for ticket sales does
not require an advance access request while it is in public preview; contact
Stripe Support if a qualifying version returns an access or feature-disabled
error.

`platform_fee_bps` cannot exceed `9999`, because an application fee must remain
strictly below a positive charge.

### External Payments

Groups whose country is not served by Stripe Connect can collect paid tickets
outside OCG. The operator allowlists ISO 3166-1 alpha-2 country codes; groups
in those countries can then opt in from group settings. Payments happen at an
event-specific URL with optional instructions, and attendees are emailed a
payment reference (the purchase ID) to include with their transfer. Organizers
match incoming transfers to that reference and mark purchases paid from the
event attendees table. Unpaid holds expire through the existing enrollment
reconcile path.

External payments are independent of the Stripe `payments` section. A
deployment can enable external payments without configuring Stripe at all, run
both side by side, or run Stripe only. When a group turns on external payments,
every paid event in that group uses the external path even if the group also
has a fiscal sponsor configured.

Helm values:

```yaml
externalPayments:
  enabled: true
  allowedCountries: [KR, NG, AR]
  defaultPaymentWindowHours: 72
  maxPaymentWindowHours: 336
```

Notes:

- `enabled: false` (the default) renders `external_payments: null` in the
  server config, which removes the synced `external_payments_config` row at
  startup.
- `enabled: true` requires a non-empty allowlist of unique ISO 3166-1 alpha-2
  country codes. An empty allowlist is invalid and the server refuses to start.
- Country codes are normalized to uppercase.
- `defaultPaymentWindowHours` and `maxPaymentWindowHours` are optional and
  default to `72` and `336`. Both must be at least `1`, and the default cannot
  exceed the max. SQL enforces the max at event validation and hold creation.
- These limits are operator-only. Group and event dashboards can pick a window
  within the max but cannot change the allowlist or the limits.

Equivalent `server.yml` section:

```yaml
external_payments:
  allowed_countries: [KR, NG, AR]
  default_payment_window_hours: 72
  max_payment_window_hours: 336
```

Omitting the section, or setting Helm `enabled: false`, is the kill switch:
the server deletes the config row and new external activity stops immediately.
Existing pending purchases stay confirmable, cancelable, and refundable, and
they keep using the live event payment URL until they complete, expire, or
are canceled.

Runtime revalidation uses the synced table. Every new hold, offer claim, paid
invitation, and waitlist promotion re-checks that the config row is present,
the group toggle is on, the group country is still allowlisted, and the event
has a payment URL. An external event that loses eligibility returns
`payment-setup-unavailable` to attendees and never falls back to Stripe.

Editing or publishing an event that still has an external payment URL is
rejected while the group is ineligible (toggle off, country delisted, or
operator config absent). Paid external events must also hold their venue in
the group country; saving or publishing one with a venue elsewhere is rejected,
and the group cannot change country or turn the toggle on while an upcoming
published external event has a venue outside the resulting group country.
Organizers can clear the URL to move the event onto Stripe validation only
after every pending external purchase has completed, expired, or been
canceled. Changing the URL or instructions while holds are open updates the
live copy shown to those attendees.

OCG does not calculate tax, issue invoices, or produce credit notes for
external purchases; the organizer handles receipts, tax, and returning money.
Attendees see an `Externally managed` label on those purchases in their
dashboard.

### Platform Fee

OCG can collect a deployment-wide platform fee on every paid event purchase.
The fee is expressed in basis points (`250` = 2.5%) and is deducted from the
group's proceeds through Stripe Connect application fees; attendees always pay
the listed ticket price.

How the fee behaves:

- Checkout initially applies the fee to the discounted ticket amount. After
  payment, OCG applies the basis points to Stripe's authoritative subtotal
  excluding tax, rounds down, and returns any excess application fee to the
  fiscal sponsor.
- Each purchase snapshots the fee amount when its checkout hold is created.
  Changing `platform_fee_bps` affects only new purchases; existing holds and
  completed purchases keep their original fee.
- Purchases with a zero final amount never collect a fee.
- When a purchase is refunded through OCG, the remaining application fee is
  returned to the fiscal sponsor and a credit note is linked to the existing
  customer refund without creating another money movement.
- Stripe settles application fees in the platform account's default currency.
  When that currency differs from the purchase currency, automatic fee returns
  fail with a diagnostic instead of moving an unverifiable amount; operators
  return the fee in the Stripe Dashboard and record the reference through
  manual financial recovery in the group's `Refunds` tab. Fee refunds that
  already exist on Stripe are reused based on their durable identity.
- Manual refund recovery records an externally arranged refund and does not
  call Stripe, so it does not return the collected application fee. Operators
  who want to return the fee for such refunds must reverse it directly in the
  Stripe Dashboard.

Application fees are collected on direct charges owned by the fiscal sponsor's
connected account.

Reference:
[Collect fees with Stripe Connect](https://docs.stripe.com/connect/direct-charges#collect-fees).

## Stripe Dashboard Setup

### Step 1: Collect the Correct API Key

In Stripe, open the Developers Dashboard and copy the secret key for the
selected mode.

Stripe documents the secret key prefixes as:

- `sk_test_...` for test mode.
- `sk_live_...` for live mode.

Reference:
[API keys](https://docs.stripe.com/keys).

### Step 2: Create Both Webhook Endpoints

Register this endpoint in Stripe:

```text
https://{YOUR_OCG_BASE_URL}/webhooks/payments
```

For example:

```text
https://ocg.example.org/webhooks/payments
```

The endpoint must be publicly reachable over HTTPS.

Register a Connect event destination separately:

```text
https://{YOUR_OCG_BASE_URL}/webhooks/payments/connected
```

The platform route accepts only events without a connected-account scope. The
Connect route requires Stripe's top-level connected account and uses a distinct
signing secret. Do not reuse or swap their secrets.

Reference:
[Receive Stripe events in your webhook endpoint](https://docs.stripe.com/webhooks).

### Step 3: Subscribe the Webhook to the Events OCG Uses

Set the webhook endpoint API version to `2024-10-28.acacia` or newer. OCG pins
its API requests to that version; configuring the event destination version as
well keeps the refund event names and payloads consistent.

Configure the connected-account event destination to send only these events:

- `checkout.session.completed`
- `checkout.session.expired`
- `invoice.paid`
- `refund.created`
- `refund.failed`
- `refund.updated`

Checkout events complete purchases or expire seat holds, invoice events attach
financial documents, and refund events reconcile sponsor-funded refunds.

Configure the platform-account endpoint to send:

- `application_fee.created`

Stripe creates direct-charge application fees asynchronously. OCG fulfills the
paid Checkout without waiting for that object, then uses the platform event to
attach the fee to its connected-account charge before fee adjustments run.
Direct-charge Checkout, invoice, and refund events belong on the Connect
destination.

Subscribing extra events is not recommended. Valid platform events that OCG
does not use are acknowledged and ignored; unsupported Connect events are
rejected so an incomplete event subscription remains visible.

References:

- [Types of events](https://docs.stripe.com/api/events/types)
- [Refund webhook event update](https://docs.stripe.com/changelog/acacia/2024-10-28/refund-webhook-update)
- [Fulfill orders](https://docs.stripe.com/checkout/fulfillment)
- [How Checkout works](https://docs.stripe.com/payments/checkout/how-checkout-works)
- [Create direct charges](https://docs.stripe.com/connect/direct-charges)
- [Refund and cancel payments](https://docs.stripe.com/refunds)

### Step 4: Copy the Endpoint Signing Secret

After creating both event destinations, reveal their signing secrets and store
them in OCG as:

- Helm: `payments.webhookSecret`
- Raw config: `payments.webhook_secret`
- Helm Connect destination: `payments.connectedWebhookSecret`
- Raw Connect destination: `payments.connected_webhook_secret`

Stripe signing secrets start with `whsec_...`.

Reference:
[Resolve webhook signature verification errors](https://docs.stripe.com/webhooks/signature).

## Fiscal Sponsors For Groups

Enabling Stripe on the server does not automatically make every group payment-ready. Each group
still needs a fiscal sponsor or steward with a compatible connected account on
the same Stripe Connect platform. One sponsor account may support multiple
groups.

OCG supports application-controlled connected accounts created through the
platform Dashboard. Account-controlled Standard accounts connected through
OAuth are not supported.

The expected flow is:

1. The group identifies a legal entity willing to act as seller and indirect-tax
   filer.
2. A platform administrator creates or opens the sponsor's
   application-controlled, Standard-like account and verifies payments and the
   required controller properties.
3. The sponsor completes onboarding, invoice business details, tax
   registrations, payout setup, and Dashboard access.
4. The group saves the sponsor's legal seller name and `acct_...` account ID in
   OCG group settings.

That group-facing flow is documented in
[docs/guides/payments-setup.md](guides/payments-setup.md).

## Current OCG Behavior

These notes come from the current OCG codebase and are worth keeping in mind
during deployment.

### Webhook Route Registration

OCG only mounts payment webhook routes when payments are enabled. The routes
are:

```text
/webhooks/payments
/webhooks/payments/connected
```

If Stripe payments are disabled, the route is not registered.

### Checkout Model

OCG creates Stripe-hosted Checkout sessions on the server side and redirects
attendees to Stripe Checkout for paid tickets.

Every positive-total purchase is a direct charge in the snapshotted fiscal
sponsor account. OCG requires an in-person or hybrid event with a complete
physical venue and a ready sponsor. Each event uses automatic ticket tax,
manual Tax Rates from the sponsor's connected account, or no tax collection.
Virtual events remain free-only. Every paid
hybrid ticket includes physical admission; it may also include virtual access,
but cannot be virtual-only.

Checkout requires the billing address, enables business tax-ID collection and
post-payment invoices, and uses `txcd_50013001` for automatic professional-event
admission. This classification covers in-person tickets and hybrid tickets that
include physical admission. An event chooses automatic Stripe Tax, manual Stripe
Tax Rates, or no tax collection. Automatic and manual modes may be inclusive
or exclusive. Manual rates are selected from active definitions in
the fiscal sponsor's connected account and are revalidated before Checkout.
Each selected rate must declare the venue country. When the venue has a state
or province code, a rate that declares one must match the venue subdivision.
Automatic-tax readiness requires an active connected-account registration
covering the venue country. OCG does not restrict venue countries, but Stripe
Tax must support the venue location; unsupported locations fail readiness and
require Manual Stripe Tax Rates. Registrations match at country level, with
exact state matching in the United States. Canadian
country-wide registrations cover all provinces, while province-specific
registrations must match exactly. The
registration lookup uses Stripe's generally available Tax Registrations API and
the standard Stripe API version, independently of the ticket-tax preview
version.
No-tax Checkout attaches no tax mechanism and must reconcile to zero tax.

Intrinsically free tickets complete locally without a currency, provider
session, webhook, or connected account. A positive base price reduced to zero
by a valid discount also completes locally while retaining its currency and
discount snapshot. If payment setup is lost, positive final-price claims are
blocked without disabling free claims or unrelated event edits.

OCG currently restricts Stripe Checkout to card payments in code. This keeps
the checkout flow aligned with the current webhook handling and avoids delayed
payment methods that require async completion events.

Automatic-tax ticket Products are immutable, seller-scoped resources keyed by
their complete Product inputs. OCG revalidates a matching cached Product in
Stripe before reuse and creates a replacement when its title, performance
location, tax code, or provider state no longer matches. Older Products and
their local cache records are retained intentionally; OCG does not archive
them, so connected accounts should expect these resources to accumulate over
time.

Reference:
[Create a Checkout Session](https://docs.stripe.com/api/checkout/sessions/create).

The fiscal sponsor owns the Customer, PaymentIntent, Charge, invoice, credit
note, refund, dispute, and Tax resources. Stripe charges its processing,
Invoicing, and Tax fees to that account. Refunds and disputes debit the sponsor's
connected account, while Stripe assumes ultimate liability when the account
cannot repay a payment-related negative balance. The sponsor remains responsible
for registrations, filing, and remittance. Stripe Tax calculation and reporting
do not make Stripe or OCG the tax filer.

### Refund Recovery

All provider-mediated refunds run through durable background work. HTTP handlers
and verified webhooks only queue or update refund state; they do not call
Stripe's refund API directly. OCG starts two provider refund workers and one
payment recovery worker. The recovery worker sweeps abandoned refund,
application-fee adjustment, and credit-note claims even when no payment provider
is configured. The refund path handles approved attendee requests,
organizer-initiated attendance cancellations, paid checkouts that can no longer
be fulfilled, and automatic refunds from event cancellation.

A late provider completion that cannot be fulfilled because its hold or offer
expired, the offer was canceled, capacity changed, or event state changed is
recorded and queued for an automatic full refund. It never creates attendance
or revives the terminal offer.

Workers look up an existing Stripe refund before creating one and reuse the
purchase's stable idempotency key. Transient failures use up to ten claims with
exponential backoff from one to thirty minutes. A claim left in `processing`
for fifteen minutes is released by the payment recovery worker. If Stripe
success was already persisted before interruption, refund recovery resumes
local finalization without creating another refund.

When this deployment has no payments provider configured, refund work remains queued and visible
to organizers. It is not discarded or treated as complete.

Payment webhooks and durable refund workers apply only to provider-backed
purchases. The enrollment reconciliation worker continues expiring offers,
releasing holds, and promoting queues independently of Stripe.

OCG validates refund webhook amounts, currencies, and PaymentIntent identifiers
against the durable purchase before accepting provider state changes. A refund
event with copied or mismatched purchase metadata cannot finalize the purchase.

Refunds are full only and are created in the snapshotted sponsor account. If
the sponsor lacks funds, OCG retains the provider-pending state, keeps it
visible in the group dashboard `Refunds` tab, and emits structured operator
logs. OCG does not send a dedicated administrator notification or fund the
sponsor account to accelerate the refund. Successful refunds queue the
application-fee return and linked credit note as separately retryable work.

Application-fee adjustments and credit notes stop after ten automatic attempts.
The group dashboard `Refunds` tab then exposes each operation as financial work
needing attention. An organizer with events write access can start another
bounded retry cycle or record the operation as completed directly in Stripe.
External completion captures the Stripe object ID, an independent recovery
reference, and the evidence reviewed, then appends an event audit entry. Exact
completion replays are idempotent; conflicting evidence is rejected.

An abandoned application-fee adjustment or credit-note claim below ten
attempts becomes retryable immediately with its existing idempotency key. It is
resumable when a compatible provider is configured, but it is not shown as
financial recovery work in the dashboard until all ten automatic attempts are
exhausted. An abandoned tenth claim is marked failed for dashboard recovery,
and its last provider error remains attached with an expiration notice that
the provider outcome is unknown.

OCG does not subscribe to, reconcile, or notify administrators about dispute
events. The fiscal sponsor monitors and handles disputes entirely in Stripe,
including evidence, balances, and any application-fee, invoice, or tax action.
OCG does not change attendance automatically in response to a dispute.

Stripe can report a refund as succeeded and later transition it to failed. When
that happens after OCG has finalized the refund locally, OCG preserves the
released seat, marks the purchase as `refund-recovery-pending`, blocks another
checkout for the same event, and records the failed provider refund for manual
recovery.

If the attendee already completed a replacement purchase before the delayed
failure arrived, that newer purchase remains valid while OCG recovers the
original refund.

OCG acknowledges `refund.failed` after persisting the terminal state and emits
a structured warning for operators. It does not submit another refund because
permanent destination failures could otherwise create an unbounded replacement
loop. Operators must arrange an alternative way to refund the attendee.

After confirming that alternative refund, an organizer with events write access
opens the group dashboard `Refunds` tab, finds the `Recovery required` row, and
selects `Complete recovery`. The organizer records the external payment
reference and a note describing the evidence reviewed. Other roles can inspect
the recovery state, but the action is disabled with an explanation of the
events write access requirement.

Completion preserves the failed Stripe attempt, records the recovery evidence,
restores the purchase to `refunded`, and appends an event audit entry. If the
provider failed before OCG finalized the refund, the same operation also
completes the pending local refund workflow and atomically queues the attendee's
completion email. Repeating the same completion with matching evidence is safe;
conflicting evidence is rejected.

Provider requests that fail without returning a Stripe refund ID remain
retryable with their original idempotency key. Exhausted transient work can be requeued by an
event administrator, including safe polling of an already-known Stripe refund ID. When an unpinned refund receives
an out-of-order success event, OCG checks the named refund's current Stripe
state before accepting it. Confirmed terminal refunds remain pinned so delayed
pending or successful events cannot revive them.

### Delayed Payment Methods

Based on the current OCG implementation, the webhook handler accepts checkout
completion and expiration events plus refund lifecycle events. Delayed payment
events such as `checkout.session.async_payment_succeeded` and
`checkout.session.async_payment_failed` are not currently covered here.

Stripe documents those async events for delayed payment methods. Because of
that, the safest deployment choice is to keep Stripe Checkout limited to
immediate payment methods unless OCG is extended to handle the async events as
well.

At the moment, that protection is enforced in code by explicitly requesting
card payments only when OCG creates Stripe Checkout sessions.

## Deployment Checklist

1. Enable Stripe Connect on your Stripe platform account.
2. Decide whether this OCG environment uses Stripe `test` or `live` mode.
3. Copy the matching Stripe secret key.
4. Confirm a Tax for ticket sales public-preview API version of
   `2026-03-25.preview` or later. Create active Tax Rate definitions in each
   connected account that will use manual tax.
5. Create the platform webhook at
   `https://{YOUR_OCG_BASE_URL}/webhooks/payments` and the Connect destination
   at `https://{YOUR_OCG_BASE_URL}/webhooks/payments/connected`.
6. Subscribe the platform endpoint to `application_fee.created` and the Connect
   destination to the Checkout completion/expiration, invoice, and refund
   events listed above.
7. Copy both distinct signing secrets and the pinned ticket-tax API version
   into OCG config.
8. Deploy OCG with `payments.enabled: true`.
9. Verify the `Payments` section appears in group settings and the event editor
   `Tickets` tab is available.
10. Create or open an application-controlled, Standard-like fiscal-sponsor
    account and verify its controller, payment, invoice, Tax, and payout
    readiness.
11. Save the sponsor's legal seller name and `acct_...` connected account ID
    for two test groups.
12. Run inclusive and exclusive test purchases, invoice delivery, a full
    refund and credit note, and pending-refund handling before enabling live
    sales.

## Troubleshooting

### Payments Section Does Not Appear In Group Settings

Check that:

- Stripe payments are enabled in OCG configuration.
- All required Stripe values are present.
- The deployment was restarted or rolled out with the new config.

Events with only free ticket types remain available without this section. Its absence
blocks only paid-capable ticket configuration and positive final-price claims.

### External Payments Section Cannot Be Enabled In Group Settings

The `External payments` section in group settings explains which condition
blocks the opt-in. Check that:

- The deployment sets `externalPayments.enabled: true` (or a non-null
  `external_payments` section) with a non-empty allowlist, and the server was
  restarted or rolled out with the new config.
- The group has a country set through its location field, and that country's
  ISO 3166-1 alpha-2 code is on the allowlist.
- The user saving the setting has group settings write access.

Eligibility is evaluated from the group's country, not from event venues. Once
eligible, paid external events must place their venue in that same country.

### Stripe Returns Signature Errors

Check that:

- The webhook endpoint secret in OCG matches the exact Stripe endpoint you
  created.
- The platform and Connect signing secrets were not swapped.
- You did not mix a Stripe CLI secret with a Dashboard-managed webhook secret.
- Test and live secrets are not crossed.

Reference:
[Resolve webhook signature verification errors](https://docs.stripe.com/webhooks/signature).

### Refund Requires Manual Recovery

Check that:

- The `refund.failed` delivery reached OCG and the purchase is marked
  `refund-recovery-pending` when local finalization had already completed.
- OCG logs contain the `provider refund requires manual recovery` warning.
- The failed refund amount, currency, and PaymentIntent match the OCG purchase.

Do not resend the event to trigger another refund. Arrange an alternative refund
method for the attendee and retain its reference and review evidence. An
organizer with events write access can then complete recovery from the group
dashboard `Refunds` tab.

### Paid Events Are Still Unavailable For A Group

These checks apply to Stripe paid events. For a group that uses external
payments, verify instead that the operator config is present, the group opt-in
is on, the group country is allowlisted, the event has a payment URL, and the
event venue is in the group country.

Check that:

- The platform administrator created a connected account for that group on the
  same Stripe Connect platform used by OCG.
- The sponsor account reports charges enabled, onboarding details submitted,
  application controller type, connected-account fee payment, Stripe
  requirement collection, Stripe liability for payment-related negative
  balances, and full Dashboard access.
- The group saved the fiscal sponsor's legal seller name and a Stripe connected
  account ID in `acct_...` format.
- The connected account belongs to the same Stripe platform used by OCG.
- The group settings were saved successfully.
- The event is in-person or hybrid with a complete physical venue and currency.
- Every paid hybrid ticket includes physical admission and is not virtual-only.
- Automatic Stripe Tax is active with a head-office address, applicable
  registrations, and a supported public-preview API version; the event selects
  active compatible Tax Rates from the sponsor account; or the event explicitly
  uses no tax collection.

If only free tickets are needed, remove positive current and future price
windows and leave the event currency and discount codes empty.
