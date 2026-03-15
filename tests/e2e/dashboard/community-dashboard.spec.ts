import { expect, test } from "@playwright/test";

import {
  TEST_USER_CREDENTIALS,
  logInWithSeededUser,
  navigateToPath,
} from "../utils";

const taxonomyCases = [
  {
    path: "/dashboard/community/regions",
    heading: "Regions",
    addButton: "Add Region",
    usedDeleteId: "delete-region-22222222-2222-2222-2222-222222222301",
    unusedDeleteId: "delete-region-22222222-2222-2222-2222-222222222302",
  },
  {
    path: "/dashboard/community/group-categories",
    heading: "Group Categories",
    addButton: "Add Group Category",
    usedDeleteId: "delete-group-category-22222222-2222-2222-2222-222222222221",
    unusedDeleteId: "delete-group-category-22222222-2222-2222-2222-222222222223",
  },
  {
    path: "/dashboard/community/event-categories",
    heading: "Event Categories",
    addButton: "Add Event Category",
    usedDeleteId: "delete-event-category-33333333-3333-3333-3333-333333333331",
    unusedDeleteId: "delete-event-category-33333333-3333-3333-3333-333333333333",
  },
] as const;

test.describe("community dashboard", () => {
  test("community team page shows seeded roles and final-admin protection", async ({
    page,
  }) => {
    await logInWithSeededUser(page, TEST_USER_CREDENTIALS.admin1);
    await navigateToPath(page, "/dashboard/community/team");

    await expect(page.getByText("Community Team", { exact: true })).toBeVisible();
    await expect(page.getByRole("button", { name: "Add member" })).toBeEnabled();

    const adminRow = page.locator("tr", { hasText: "E2E Admin One" });
    await expect(adminRow.locator("select")).toBeDisabled();
    await expect(adminRow.getByTitle("At least one accepted admin is required.")).toBeVisible();

    await expect(page.locator("tr", { hasText: "E2E Groups Manager One" })).toContainText(
      "groups-manager",
    );
    await expect(page.locator("tr", { hasText: "E2E Community Viewer One" })).toContainText(
      "viewer",
    );
    await expect(page.locator("tr", { hasText: "E2E Pending One" })).toContainText(
      "Invitation sent",
    );
  });

  for (const taxonomyCase of taxonomyCases) {
    test(`admin can distinguish used and unused entries on ${taxonomyCase.heading}`, async ({
      page,
    }) => {
      await logInWithSeededUser(page, TEST_USER_CREDENTIALS.admin1);
      await navigateToPath(page, taxonomyCase.path);

      await expect(page.getByText(taxonomyCase.heading, { exact: true })).toBeVisible();
      await expect(
        page.getByRole("button", { name: taxonomyCase.addButton }),
      ).toBeEnabled();
      await expect(page.locator(`#${taxonomyCase.usedDeleteId}`)).toBeDisabled();
      await expect(page.locator(`#${taxonomyCase.unusedDeleteId}`)).toBeEnabled();
    });

    test(`viewer sees read-only controls on ${taxonomyCase.heading}`, async ({ page }) => {
      await logInWithSeededUser(page, TEST_USER_CREDENTIALS.communityViewer1);
      await navigateToPath(page, taxonomyCase.path);

      await expect(page.getByText(taxonomyCase.heading, { exact: true })).toBeVisible();
      await expect(
        page.getByRole("button", { name: taxonomyCase.addButton }),
      ).toBeDisabled();
      await expect(page.locator(`#${taxonomyCase.unusedDeleteId}`)).toBeDisabled();
    });
  }
});
