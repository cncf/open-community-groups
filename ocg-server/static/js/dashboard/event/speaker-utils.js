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
  return list.map((speaker) => ({
    ...speaker,
    featured: !!speaker.featured,
  }));
};

/**
 * Builds a comparable key for a speaker/user object.
 * @param {Object} item
 * @returns {string}
 */
export const speakerKey = (item) => String(item?.user_id ?? item?.username ?? "");

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
