/**
 * Computes initials from a user's name, with username fallback.
 * @param {string|null|undefined} name Full name, when available.
 * @param {string} username Username used as fallback.
 * @param {number} count Initials count. Defaults to 2.
 * @returns {string} Initials string.
 */
export const computeUserInitials = (name, username, count = 2) => {
  const cleanName = (name || "").trim();
  if (cleanName.length === 0) {
    return (username || "").charAt(0).toUpperCase();
  }

  const parts = cleanName.split(/\s+/);
  let initials = "";
  if (parts.length > 0 && parts[0].length > 0) {
    initials += parts[0][0].toUpperCase();
  }
  if (count >= 2 && parts.length > 1 && parts[parts.length - 1].length > 0) {
    initials += parts[parts.length - 1][0].toUpperCase();
  }
  return initials;
};
