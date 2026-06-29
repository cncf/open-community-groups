/**
 * Builds the detail payload consumed by user-info-modal.
 * @param {Object} user User profile payload.
 * @param {Object} options Modal rendering options.
 * @param {boolean} options.bioIsHtml Whether the bio should render as trusted HTML.
 * @returns {Object} User modal event detail.
 */
export const buildUserModalEventDetail = (user, { bioIsHtml = false } = {}) => ({
  name: user?.name,
  username: user?.username,
  imageUrl: user?.photo_url,
  jobTitle: user?.title,
  company: user?.company,
  bio: user?.bio,
  bioIsHtml,
  blueskyUrl: user?.bluesky_url,
  facebookUrl: user?.facebook_url,
  githubUrl: user?.github_url,
  linkedinUrl: user?.linkedin_url,
  provider: user?.provider,
  twitterUrl: user?.twitter_url,
  websiteUrl: user?.website_url,
});

/**
 * Dispatches the user-info modal open event from the provided target.
 * @param {EventTarget} target Event target that should emit the modal event.
 * @param {Object} user User profile payload.
 * @param {Object} options Modal rendering options.
 */
export const dispatchUserModalOpenEvent = (target, user, options = {}) => {
  target.dispatchEvent(
    new CustomEvent("open-user-modal", {
      detail: buildUserModalEventDetail(user, options),
      bubbles: true,
      composed: true,
    }),
  );
};
