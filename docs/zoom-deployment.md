<!-- markdownlint-disable MD013 -->

# Zoom Meetings Deployment Guide

This document is for OCG operators and deployment maintainers.

It is intentionally unlisted from the public docs navigation because it covers
server configuration, Zoom app setup, webhook configuration, and internal
operational caveats.

## What This Enables

Once this setup is complete:

- OCG can create Zoom meetings automatically for supported events and sessions.
- OCG can end automatically created Zoom meetings when their scheduled end time
  is reached.
- OCG can receive Zoom recording webhooks and save the shared recording URL.
- Group administrators can use `Create meeting automatically` with provider
  `Zoom`.

## Zoom Requirements

OCG's Zoom integration is built around:

- A Zoom Server-to-Server OAuth app for API access.
- A Zoom webhook endpoint for URL validation and recording updates.
- A pool of Zoom host users that OCG can schedule meetings under.

You need:

- A Zoom account with API app management access.
- A Server-to-Server OAuth app in Zoom.
- A public HTTPS URL for your OCG server.
- One or more Zoom host users that can be used for scheduled meetings.
- A decision about the participant limit your Zoom plan supports.

Useful Zoom references:

- [Internal apps (Server-to-server)](https://developers.zoom.us/docs/internal-apps/)
- [Meetings APIs](https://developers.zoom.us/docs/api/meetings/)
- [Webhook URL validation enforcement and verification changes](https://developers.zoom.us/changelog/platform/verification-changes-webhook/)
- [Enabling cloud recording](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0063923)
- [Managing cloud recording settings](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0065362)
- [Managing and sharing cloud recordings](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0067567)
- [Hosting multiple meetings simultaneously](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0068522)

## OCG Configuration

### Helm Values

The Helm chart exposes Zoom configuration in `charts/ocg/values.yaml`:

```yaml
meetings:
  zoom:
    enabled: true
    accountId: "{YOUR_ZOOM_ACCOUNT_ID}"
    clientId: "{YOUR_ZOOM_CLIENT_ID}"
    clientSecret: "{YOUR_ZOOM_CLIENT_SECRET}"
    hostPoolUsers:
      - "host1@example.org"
      - "host2@example.org"
    maxParticipants: 100
    maxSimultaneousMeetingsPerHost: 1
    webhookSecretToken: "{YOUR_ZOOM_WEBHOOK_SECRET_TOKEN}"
```

Notes:

- Set `enabled: true` to make Zoom available in OCG automatic meeting flows.
- `accountId`, `clientId`, and `clientSecret` come from the Zoom
  Server-to-Server OAuth app.
- `hostPoolUsers` must be a non-empty list of unique email addresses.
- `maxParticipants` should match the real limit of your Zoom plan.
- `maxSimultaneousMeetingsPerHost` must be at least `1`; set a higher value
  only if your Zoom plan and any purchased add-ons allow more concurrent
  meetings per host.
- `webhookSecretToken` is required to verify Zoom webhook signatures.

### Raw Server Config

If you are not using the Helm chart, the equivalent `server.yml` section is:

```yaml
meetings:
  zoom:
    enabled: true
    account_id: "{YOUR_ZOOM_ACCOUNT_ID}"
    client_id: "{YOUR_ZOOM_CLIENT_ID}"
    client_secret: "{YOUR_ZOOM_CLIENT_SECRET}"
    host_pool_users:
      - "host1@example.org"
      - "host2@example.org"
    max_participants: 100
    max_simultaneous_meetings_per_host: 1
    webhook_secret_token: "{YOUR_ZOOM_WEBHOOK_SECRET_TOKEN}"
```

The current server validates that:

- `host_pool_users` is not empty when Zoom is enabled.
- Every `host_pool_users` value is a valid email address.
- `host_pool_users` does not contain duplicates.
- `max_simultaneous_meetings_per_host` is at least `1`.
  Higher values depend on your Zoom plan and any purchased add-ons.

## Zoom App Setup

### Step 1: Create a Server-to-Server OAuth App

Create a Zoom Server-to-Server OAuth app for the OCG deployment.

OCG uses that app to request access tokens and call the Zoom API for meeting
creation, updates, deletion, and end-meeting operations.

Copy these values from Zoom:

- `Account ID`
- `Client ID`
- `Client Secret`

Store them in OCG as:

- Helm: `meetings.zoom.accountId`, `meetings.zoom.clientId`,
  `meetings.zoom.clientSecret`
- Raw config: `meetings.zoom.account_id`, `meetings.zoom.client_id`,
  `meetings.zoom.client_secret`

Reference: [Internal apps (Server-to-server)](https://developers.zoom.us/docs/internal-apps/).

### Step 2: Choose the Host Pool Users

OCG does not turn event organizers or speaker emails into Zoom hosts
automatically.

Instead, OCG selects an available host from the configured `hostPoolUsers`
list when it creates a meeting.

Choose host users that:

- Exist in the Zoom account used by the OAuth app.
- Are allowed to schedule the kinds of meetings you want OCG to create.
- Can safely be used by automation.

If you expect overlapping meetings, increase the size of the host pool or raise
`maxSimultaneousMeetingsPerHost` to match the concurrency your Zoom plan and
any purchased add-ons actually support.

Reference: [Hosting multiple meetings simultaneously](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0068522).

## Zoom Account Settings

Use these Zoom account settings for OCG-created meetings and recordings.

### Meeting Defaults

Configure these settings in Zoom:

- `Require a passcode when scheduling new meetings`: enabled
- `Embed passcode in invite link for one-click join`: enabled
- `Allow participants to join before host`: enabled
- `Participants can join`: `15 minutes before start time`

When Zoom shows multiple `join before host` choices, select the option that
lets participants join `15 minutes before start time`.

These defaults align with the way OCG currently creates Zoom meetings:

- OCG requests a generated default password for new meetings.
- OCG enables `join_before_host`.
- OCG sets join-before-host time to `15` minutes.

Reference: [Meetings APIs](https://developers.zoom.us/docs/api/meetings/).

### Recording Defaults

Configure these settings in Zoom:

- `Cloud recording`: enabled
- `Zoom Meeting`: enabled under cloud recording
- `Automatic recording`: enabled
- `Record in the cloud`: selected

These defaults align with current OCG behavior because OCG requests cloud
recording for created meetings and expects Zoom to send a
`recording.completed` webhook when the recording is ready.

References:

- [Enabling cloud recording](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0063923)
- [Managing cloud recording settings](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0065362)

### Recording Sharing Defaults

Configure these settings in Zoom:

- `Allow cloud recording sharing`: enabled
- `Require users to authenticate before viewing cloud recordings`: disabled
- `Require passcode to access shared cloud recordings`: disabled

These settings are recommended so Zoom can produce a usable shared recording
URL for OCG to store when the `recording.completed` webhook arrives.

If recording sharing is disabled, or if Zoom does not generate a shareable URL,
OCG cannot populate the recording link from the webhook payload.

References:

- [Managing cloud recording settings](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0065362)
- [Managing and sharing cloud recordings](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0067567)

## Zoom Webhook Setup

### Step 1: Register the Webhook Endpoint

Register this endpoint in Zoom:

```text
https://{YOUR_OCG_BASE_URL}/webhooks/zoom
```

The endpoint must be publicly reachable over HTTPS.

### Step 2: Set the Webhook Secret Token

Configure a Zoom webhook secret token and store it in OCG as:

- Helm: `meetings.zoom.webhookSecretToken`
- Raw config: `meetings.zoom.webhook_secret_token`

OCG uses that token to verify the `x-zm-signature` header on incoming Zoom
webhooks.

Reference: [Webhook URL validation enforcement and verification changes](https://developers.zoom.us/changelog/platform/verification-changes-webhook/).

### Step 3: Subscribe the Webhook to the Events OCG Uses

Configure the Zoom webhook to send these events:

- `endpoint.url_validation`
- `recording.completed`

These are the Zoom webhook events the current OCG implementation handles.

## Current OCG Behavior

### Meeting Creation Defaults

When OCG creates or updates a Zoom meeting, it currently applies these values:

- Scheduled meeting type
- Default password enabled
- Automatic recording set to `cloud`
- Join before host enabled
- Join-before-host time set to `15` minutes
- Mute upon entry enabled
- Participant video disabled
- Waiting room disabled

### Automatic Meeting Constraints

Automatic Zoom meetings currently require:

- Event type `virtual` or `hybrid`
- A start and end time
- A duration between `5` and `720` minutes
- Event capacity that does not exceed the configured `maxParticipants`

### Webhook Route Registration

OCG only mounts the Zoom webhook route when Zoom is enabled. The route is:

```text
/webhooks/zoom
```

If Zoom is disabled, the route is not registered.

### Recording URL Handling

OCG currently listens for `recording.completed` and stores the `share_url`
provided by Zoom.

If the webhook payload has no `share_url`, OCG skips the recording-link update.

### Host Controls Limitation

Due to current technical limitations, host controls are not available in
automatically created Zoom meetings.

## Troubleshooting

### Zoom Is Not Available In Automatic Meeting Setup

Check:

- Zoom is enabled in OCG configuration.
- All required Zoom credentials are present.
- `hostPoolUsers` is configured with valid, unique emails.
- The deployment was restarted or rolled out with the new config.

### Zoom Webhook Validation Or Signature Checks Fail

Check:

- The webhook endpoint is exactly `https://{YOUR_OCG_BASE_URL}/webhooks/zoom`.
- The webhook secret token in OCG matches the secret configured in Zoom.
- The server is publicly reachable over HTTPS.

### Recording Links Are Missing

Check:

- `Cloud recording` is enabled in Zoom.
- `Automatic recording` is enabled and set to `Record in the cloud`.
- `Allow cloud recording sharing` is enabled.
- The webhook is subscribed to `recording.completed`.
- Zoom has finished processing the recording.
