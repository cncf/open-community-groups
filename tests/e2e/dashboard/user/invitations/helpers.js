/** Returns the Invitations link of the dashboard navigation. */
export const getInvitationsMenuLink = (page) =>
  page.getByRole("navigation", { name: "Dashboard navigation" }).getByRole("link", { name: /^Invitations/ });

/** Opens the actions menu for an event offer row. */
export const openEventOfferActions = async (offerRow) => {
  await offerRow.getByLabel(/Open offer actions/).click();
};

/**
 * Reads the pending count from the Invitations menu link's accessible name.
 * @returns {Promise<number>} Pending invitations count, or 0 when none is shown.
 */
export const readInvitationsMenuCount = async (page) => {
  const snapshot = await getInvitationsMenuLink(page).ariaSnapshot();
  const accessibleName = snapshot.match(/link "([^"]*)"/)?.[1] ?? "";
  const count = accessibleName.match(/ (\d+) pending$/);
  return count ? Number(count[1]) : 0;
};
