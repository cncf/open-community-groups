/**
 * Normalizes a single speaker entry to a flat shape.
 * @param {any} speaker
 * @returns {Object|null}
 */
const normalizeSpeaker = (speaker) => {
  if (!speaker || typeof speaker !== "object") {
    return null;
  }

  const normalized = {
    ...(speaker.user && typeof speaker.user === "object" ? speaker.user : {}),
    ...speaker,
    featured: !!speaker.featured,
  };

  delete normalized.user;

  if (!normalized.user_id && !normalized.username) {
    return null;
  }

  return normalized;
};

/**
 * Normalizes speakers list ensuring array shape and boolean featured flag.
 * Accepts stringified JSON or array-like values.
 * @param {any} value
 * @returns {Array}
 */
export const normalizeSpeakers = (value) => {
  let list = value;
  if (typeof list === "string") {
    try {
      list = JSON.parse(list || "[]");
    } catch (_) {
      list = [];
    }
  }
  if (!Array.isArray(list)) return [];
  return list.map((speaker) => normalizeSpeaker(speaker)).filter(Boolean);
};

/**
 * Builds a comparable key for a speaker/user object.
 * @param {Object} item
 * @returns {string}
 */
export const speakerKey = (item) => {
  const normalized = normalizeSpeaker(item);
  return String(normalized?.user_id ?? normalized?.username ?? "");
};

/**
 * Checks if speakers list already contains the provided user.
 * @param {Array} speakers
 * @param {Object} user
 * @returns {boolean}
 */
export const hasSpeaker = (speakers, user) => {
  const target = speakerKey(user);
  if (!target.length) return false;
  return (speakers || []).some((speaker) => speakerKey(speaker) === target);
};
