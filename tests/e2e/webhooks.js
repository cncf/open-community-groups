import { createHmac } from "node:crypto";

// Evaluated while building the exported constants, so these helpers come first.
/** Returns a required environment variable, failing with a webhook-specific message. */
const requireEnv = (name) => {
  const value = process.env[name];

  if (!value) {
    throw new Error(`${name} is required to sign provider webhooks (run through the justfile recipes)`);
  }

  return value;
};

/** Returns the current Unix timestamp in seconds. */
const nowInSeconds = () => Math.floor(Date.now() / 1000);

/** Relative paths of the provider webhook endpoints exposed by the server. */
export const WEBHOOK_ENDPOINTS = {
  stripeConnected: "/webhooks/payments/connected",
  stripePlatform: "/webhooks/payments",
  zoom: "/webhooks/zoom",
};

/** Webhook secrets shared with `tests/e2e/config/server.yml` through the justfile contract. */
export const WEBHOOK_SECRETS = {
  stripeConnected: requireEnv("OCG_E2E_STRIPE_CONNECTED_WEBHOOK_SECRET"),
  stripePlatform: requireEnv("OCG_E2E_STRIPE_WEBHOOK_SECRET"),
  zoom: requireEnv("OCG_E2E_ZOOM_WEBHOOK_SECRET"),
};

/**
 * Builds a Stripe `Stripe-Signature` header (`t=<unix>,v1=<hmac>`) over the exact body bytes.
 * `timestamp` can be overridden to exercise the stale-timestamp rejection path.
 */
export const signStripe = (body, secret, { timestamp = nowInSeconds() } = {}) => {
  const signature = createHmac("sha256", secret).update(`${timestamp}.${body}`).digest("hex");

  return `t=${timestamp},v1=${signature}`;
};

/**
 * Signs and posts a Stripe webhook, sending the same bytes that were signed.
 * Pass `signature` to send a precomputed (e.g. invalid) header instead of signing.
 */
export const postStripe = async (request, { endpoint, body, secret, signature, timestamp }) => {
  const payload = typeof body === "string" ? body : JSON.stringify(body);

  return request.post(endpoint, {
    data: payload,
    headers: {
      "content-type": "application/json",
      "stripe-signature": signature ?? signStripe(payload, secret, { timestamp }),
    },
  });
};

/** Builds the Zoom `x-zm-signature` header (`v0=<hmac>` over `v0:<timestamp>:<body>`). */
export const signZoom = (body, secret, timestamp) => {
  const signature = createHmac("sha256", secret).update(`v0:${timestamp}:${body}`).digest("hex");

  return `v0=${signature}`;
};

/**
 * Signs and posts a Zoom webhook with the timestamp header the server validates against.
 * Pass `signature` to send a precomputed (e.g. invalid) header instead of signing.
 */
export const postZoom = async (request, { body, secret, signature, timestamp = nowInSeconds() }) => {
  const payload = typeof body === "string" ? body : JSON.stringify(body);

  return request.post(WEBHOOK_ENDPOINTS.zoom, {
    data: payload,
    headers: {
      "content-type": "application/json",
      "x-zm-request-timestamp": String(timestamp),
      "x-zm-signature": signature ?? signZoom(payload, secret, timestamp),
    },
  });
};

/** Computes the Zoom URL-validation response token for a `plainToken` challenge. */
export const zoomEncryptedToken = (plainToken, secret) =>
  createHmac("sha256", secret).update(plainToken).digest("hex");
