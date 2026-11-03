import { expect, test } from "../../fixtures.js";

import { expectAriaSnapshot, expectPageLayout } from "../../snapshots.js";
import { navigateToPath } from "../../utils.js";

const ACTIVE_CREDENTIAL_ID = "dadadada-dada-dada-dada-dadadadada02";

test.describe("public badge credential page ARIA snapshots", () => {
  test("matches the desktop credential", async ({ page }) => {
    // Load the active credential and check its layout.
    const credential = await openCredential(page);

    // Capture the credential; its award date follows the seed day.
    await expectAriaSnapshot(page, credential, "badge-credential");
  });

  test("matches the mobile credential @mobile", async ({ page }) => {
    // Load the active credential and check its layout.
    const credential = await openCredential(page);

    // Capture the credential; its award date follows the seed day.
    await expectAriaSnapshot(page, credential, "badge-credential");
  });
});

/** Opens the seeded active credential, checks its layout and returns the credential region. */
const openCredential = async (page) => {
  const credential = page.getByRole("region", { name: "Host" });
  await navigateToPath(page, `/badges/credentials/${ACTIVE_CREDENTIAL_ID}`);
  await expect(page.getByRole("heading", { name: "Host" })).toBeVisible();
  await expectPageLayout(page, { regions: [credential] });
  return credential;
};
