const CREDENTIAL_PREFIX = "ocg-check-in:v1:";
const DEFAULT_COOLDOWN_MS = 1800;
const DEFAULT_DEDUPE_MS = 3000;

/**
 * Creates the camera-independent continuous scan controller.
 * @param {Object} options Controller dependencies.
 * @returns {Object} Scan controller.
 */
export const createScanStateMachine = ({
  audio,
  cooldownMs = DEFAULT_COOLDOWN_MS,
  dedupeMs = DEFAULT_DEDUPE_MS,
  eventId,
  now = () => Date.now(),
  onFeedback = () => {},
  onReady = () => {},
  postCredential,
  scanner,
  schedule = (callback, delay) => window.setTimeout(callback, delay),
  unschedule = (timer) => window.clearTimeout(timer),
}) => {
  let active = false;
  let cooldownTimer = null;
  let inFlight = false;
  let muted = false;
  let tornDown = false;
  const recentCredentials = new Map();

  const beginCooldown = (feedback, sound) => {
    onFeedback(feedback);
    if (!muted) {
      audio?.play?.(sound);
    }
    cooldownTimer = schedule(() => {
      cooldownTimer = null;
      if (active) {
        onReady();
      }
    }, cooldownMs);
  };

  const handleDecode = async (result) => {
    const credential = typeof result === "string" ? result : result?.data;
    if (!active || inFlight || cooldownTimer !== null) {
      return false;
    }

    const decodedAt = now();
    for (const [recentCredential, lastSeenAt] of recentCredentials) {
      if (decodedAt - lastSeenAt >= dedupeMs) {
        recentCredentials.delete(recentCredential);
      }
    }
    const lastSeenAt = recentCredentials.get(credential);
    if (lastSeenAt !== undefined && decodedAt - lastSeenAt < dedupeMs) {
      return false;
    }
    recentCredentials.set(credential, decodedAt);

    const validation = validateCredential(credential, eventId);
    if (!validation.ok) {
      beginCooldown({ kind: "error", message: validation.message }, "error");
      return false;
    }

    inFlight = true;
    try {
      const response = await postCredential(credential);
      if (!active) return false;
      const attendeeName = response.attendee?.name || response.attendee?.username || "Attendee";
      const alreadyCheckedIn = response.outcome === "already-checked-in";
      beginCooldown(
        {
          attendeeName,
          kind: alreadyCheckedIn ? "error" : "success",
          message: alreadyCheckedIn ? "Already checked in" : "Checked in",
          ticketTitle: response.ticket_title || "Ticket information unavailable",
        },
        alreadyCheckedIn ? "neutral" : "success",
      );
      return true;
    } catch (error) {
      recentCredentials.delete(credential);
      if (!active) return false;
      beginCooldown(
        {
          kind: "error",
          message: error?.message || "Check-in failed. Try again or use manual check-in.",
        },
        "error",
      );
      return false;
    } finally {
      inFlight = false;
    }
  };

  return {
    get muted() {
      return muted;
    },
    async start() {
      if (tornDown) return;
      active = true;
      try {
        await scanner?.start?.();
        if (active) onReady();
      } catch (error) {
        active = false;
        throw error;
      }
    },
    handleDecode,
    setMuted(nextMuted) {
      muted = Boolean(nextMuted);
      return muted;
    },
    teardown() {
      if (tornDown) return;
      tornDown = true;
      active = false;
      inFlight = false;
      if (cooldownTimer !== null) {
        unschedule(cooldownTimer);
        cooldownTimer = null;
      }
      recentCredentials.clear();
      scanner?.destroy?.();
      audio?.close?.();
    },
  };
};

/**
 * Validates a decoded credential for the scanner's selected event.
 * @param {string} credential Decoded QR value.
 * @param {string} eventId Selected event identifier.
 * @returns {{ok: boolean, message?: string}} Validation result.
 */
export const validateCredential = (credential, eventId) => {
  if (typeof credential !== "string" || !credential.startsWith(CREDENTIAL_PREFIX)) {
    return { ok: false, message: "This is not an Open Community Groups check-in code." };
  }

  const payload = credential.slice(CREDENTIAL_PREFIX.length);
  const fields = payload.split(":");
  if (fields.length !== 2 || !fields[0] || !fields[1]) {
    return { ok: false, message: "This check-in code is malformed." };
  }
  if (fields[0].toLowerCase() !== eventId.toLowerCase()) {
    return { ok: false, message: "This check-in code belongs to a different event." };
  }

  return { ok: true };
};
