import { expect, test } from "../../fixtures.js";

import { TEST_GROUP_IDS, buildE2eUrl, navigateToPath } from "../../utils.js";

const ACTIVE_CREDENTIAL_ID = "dadadada-dada-dada-dada-dadadadada02";
const BADGE_STATUS_LIST_ID = "cacacaca-caca-caca-caca-cacacacaca01";
const MEMBER_HOST_CREDENTIAL_ID = "dadadada-dada-dada-dada-dadadadada06";
const REVOKED_CREDENTIAL_ID = "dadadada-dada-dada-dada-dadadadada04";

test.describe("public badge credential page", () => {
  test("credential page exposes complete award copy and artwork", async ({
    page,
  }) => {
    // Load an active public badge credential.
    await navigateToPath(page, `/badges/credentials/${ACTIVE_CREDENTIAL_ID}`);

    // Verify its artwork, issuer metadata, award date, and criteria copy.
    await expect(page).toHaveTitle("Host badge");
    await expect(page.getByAltText("Host badge artwork")).toBeVisible();
    await expect(
      page.getByText(
        "Recognizes contributors who host Platform Ops Meetup events.",
        { exact: true },
      ),
    ).toBeVisible();
    await expect(page.getByText("Issued by", { exact: true })).toBeVisible();
    await expect(page.getByText("Awarded", { exact: true })).toBeVisible();
    // The award date is seeded relative to load time, so assert the format only.
    await expect(page.locator('dt:text-is("Awarded") + dd')).toHaveText(
      /^\s*\d{4}-\d{2}-\d{2}\s*$/,
    );
    await expect(page.getByText("Criteria", { exact: true })).toBeVisible();
    await expect(
      page.getByText("Serve as a host for a Platform Ops Meetup event.", {
        exact: true,
      }),
    ).toBeVisible();
  });

  test("credential pages expose active and revoked state without account identifiers", async ({
    page,
  }) => {
    // Check an active public credential.
    await navigateToPath(page, `/badges/credentials/${ACTIVE_CREDENTIAL_ID}`);
    await expect(page.getByRole("heading", { name: "Host" })).toBeVisible();
    await expect(
      page.getByText("Active credential", { exact: true }),
    ).toBeVisible();
    await expect(
      page.getByText("Platform Ops Meetup (Platform Engineering Community)", {
        exact: true,
      }),
    ).toBeVisible();

    // Verify portable account identifiers are absent from the public page.
    await expect(page.locator("body")).not.toContainText(
      "e2e-organizer-1@example.com",
    );
    await expect(page.locator("body")).not.toContainText("e2e-organizer-1");

    // Check a previously revoked credential remains public history.
    await navigateToPath(page, `/badges/credentials/${REVOKED_CREDENTIAL_ID}`);
    await expect(page.getByRole("heading", { name: "Speaker" })).toBeVisible();
    await expect(
      page.getByText("Permanently revoked", { exact: true }),
    ).toBeVisible();
  });
});
