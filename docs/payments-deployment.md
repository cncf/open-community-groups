<!-- markdownlint-disable MD013 -->

# Stripe Payments Deployment Guide

This document is for OCG operators and deployment maintainers.

It is intentionally unlisted from the public docs navigation because it covers
server configuration, Stripe platform setup, and operational caveats.

## What This Enables

Once this setup is complete:

- OCG can create Stripe Checkout sessions for paid event purchases.
- OCG can verify Stripe webhook signatures.
- Groups can store Stripe connected account IDs in group settings.
- Group administrators can create ticketed events and process refunds in OCG.

## Stripe Requirements

OCG's payments integration is built around Stripe Connect and Stripe Checkout.

You need:

- A Stripe platform account with Connect enabled.
- Access to the Stripe Dashboard for that platform account.
- A public HTTPS URL for your OCG server.
- A decision about whether this deployment is running in Stripe `test` mode or
  Stripe `live` mode.

Useful Stripe references:

- [Platforms and marketplaces with Stripe Connect](https://docs.stripe.com/connect)
- [How Connect works](https://docs.stripe.com/connect/how-connect-works)
- [Use a prebuilt Stripe-hosted payment page](https://docs.stripe.com/payments/checkout)
- [API keys](https://docs.stripe.com/keys)
- [Receive Stripe events in your webhook endpoint](https://docs.stripe.com/webhooks)

## OCG Configuration

### Helm Values

The Helm chart exposes Stripe configuration in `charts/ocg/values.yaml`:

```yaml
payments:
  enabled: true
  provider: stripe
  mode: test
  publishableKey: "pk_test_..."
  secretKey: "sk_test_..."
  webhookSecret: "whsec_..."
```

Notes:

- Set `enabled: true` to make payments available in OCG.
- Set `provider: stripe` because OCG currently supports one configured payments
  provider at a time and Stripe is the only implemented provider.
- Use `mode: test` with Stripe test keys.
- Use `mode: live` only with live Stripe keys.
- `publishableKey`, `secretKey`, and `webhookSecret` are all required when
  payments are enabled.

### Raw Server Config

If you are not using the Helm chart, the equivalent `server.yml` section is:

```yaml
payments:
  provider: stripe
  mode: test
  publishable_key: "pk_test_..."
  secret_key: "sk_test_..."
  webhook_secret: "whsec_..."
```

The current server validates that `publishable_key`, `secret_key`, and
`webhook_secret` are non-empty when Stripe payments are configured.

## Stripe Dashboard Setup

### Step 1: Collect the Correct API Keys

In Stripe, open the Developers Dashboard and copy:

- The publishable key for the selected mode.
- The secret key for the selected mode.

Stripe documents the key prefixes as:

- `pk_test_...` and `sk_test_...` for test mode.
- `pk_live_...` and `sk_live_...` for live mode.

Reference:
[API keys](https://docs.stripe.com/keys).

### Step 2: Create the Webhook Endpoint

Register this endpoint in Stripe:

```text
https://{YOUR_OCG_BASE_URL}/webhooks/payments
```

For example:

```text
https://ocg.example.org/webhooks/payments
```

The endpoint must be publicly reachable over HTTPS.

Reference:
[Receive Stripe events in your webhook endpoint](https://docs.stripe.com/webhooks).

### Step 3: Subscribe the Webhook to the Events OCG Uses

Configure the Stripe webhook endpoint to send only these events:

- `checkout.session.completed`
- `checkout.session.expired`

These are the only Stripe Checkout events the current OCG payments handler
accepts for purchase completion and expired seat holds.

Subscribing extra Stripe events is not recommended here because unsupported
events are currently rejected by the webhook handler.

References:

- [Types of events](https://docs.stripe.com/api/events/types)
- [Fulfill orders](https://docs.stripe.com/checkout/fulfillment)
- [How Checkout works](https://docs.stripe.com/payments/checkout/how-checkout-works)

### Step 4: Copy the Endpoint Signing Secret

After creating the Stripe webhook endpoint, reveal its signing secret and store
it in OCG as:

- Helm: `payments.webhookSecret`
- Raw config: `payments.webhook_secret`

Stripe signing secrets start with `whsec_...`.

Reference:
[Resolve webhook signature verification errors](https://docs.stripe.com/webhooks/signature).

## Connected Accounts For Groups

Enabling Stripe on the server does not automatically make every group
payment-ready.

Each group still needs its own Stripe connected account on the same Stripe
Connect platform used by this OCG deployment.

The expected flow is:

1. A group administrator asks the platform administrator to create a Stripe
   connected account for the group.
2. The platform administrator creates that connected account and gives the
   group administrator access to it in Stripe.
3. The group administrator completes Stripe onboarding and payout details for
   that connected account.
4. The group administrator copies the `acct_...` connected account ID from
   Stripe and saves it in OCG group settings.

That group-facing flow is documented in
[docs/guides/payments-setup.md](guides/payments-setup.md).

## Current OCG Behavior

These notes come from the current OCG codebase and are worth keeping in mind
during deployment.

### Webhook Route Registration

OCG only mounts the payments webhook route when payments are enabled. The
route is:

```text
/webhooks/payments
```

If Stripe payments are disabled, the route is not registered.

### Checkout Model

OCG creates Stripe-hosted Checkout sessions on the server side and redirects
attendees to Stripe Checkout for paid tickets.

OCG currently restricts Stripe Checkout to card payments in code. This keeps
the checkout flow aligned with the current webhook handling and avoids delayed
payment methods that require async completion events.

Reference:
[Create a Checkout Session](https://docs.stripe.com/api/checkout/sessions/create).

### Delayed Payment Methods

Based on the current OCG implementation, the webhook handler accepts
`checkout.session.completed` and `checkout.session.expired` events. Delayed
payment events such as `checkout.session.async_payment_succeeded` and
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
3. Copy the matching Stripe publishable and secret keys.
4. Create a Stripe webhook endpoint pointing to
   `https://{YOUR_OCG_BASE_URL}/webhooks/payments`.
5. Subscribe the webhook only to `checkout.session.completed` and
   `checkout.session.expired`.
6. Copy the webhook signing secret into OCG config.
7. Deploy OCG with `payments.enabled: true`.
8. Verify the `Payments` section appears in group settings.
9. Create a Stripe connected account for a test group and give that group's
   administrator access to it.
10. Complete Stripe onboarding and payout setup for the test group's connected
   account.
11. Save the `acct_...` connected account ID in the test group's settings.
12. Run a full paid-ticket flow in Stripe test mode before going live.

## Troubleshooting

### Payments Section Does Not Appear In Group Settings

Check:

- Stripe payments are enabled in OCG configuration.
- All required Stripe values are present.
- The deployment was restarted or rolled out with the new config.

### Stripe Returns Signature Errors

Check:

- The webhook endpoint secret in OCG matches the exact Stripe endpoint you
  created.
- You did not mix a Stripe CLI secret with a Dashboard-managed webhook secret.
- Test and live secrets are not crossed.

Reference:
[Resolve webhook signature verification errors](https://docs.stripe.com/webhooks/signature).

### Paid Events Are Still Unavailable For A Group

Check:

- The platform administrator created a connected account for that group on the
  same Stripe Connect platform used by OCG.
- The group administrator has completed onboarding and payout setup for that
  connected account in Stripe.
- The group saved a Stripe connected account ID in `acct_...` format.
- The connected account belongs to the same Stripe platform used by OCG.
- The group settings were saved successfully.
