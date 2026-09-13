/** Opens the actions menu for an event offer row. */
export const openEventOfferActions = async (offerRow) => {
  await offerRow.getByLabel(/Open offer actions/).click();
};
