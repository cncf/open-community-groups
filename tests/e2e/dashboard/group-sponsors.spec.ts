import { expect, test } from "../fixtures";

import { navigateToPath } from "../utils";

const TECH_CORP_SPONSOR_ID = "66666666-6666-6666-6666-666666666601";
const ORIGINAL_SPONSOR_NAME = "Tech Corp";
const UPDATED_SPONSOR_NAME = "Tech Corp Updated";
const ORIGINAL_SPONSOR_WEBSITE = "https://techcorp.example.com";
const UPDATED_SPONSOR_WEBSITE = "https://updated-techcorp.example.com";

test.describe("group sponsors dashboard", () => {
  test("organizer can update a sponsor and restore the original values", async ({
    organizerGroupPage,
  }) => {
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=sponsors");

    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Sponsors", { exact: true })).toBeVisible();

    const originalRow = dashboardContent.locator("tr", { hasText: ORIGINAL_SPONSOR_NAME });
    await expect(originalRow).toBeVisible();
    await expect(originalRow).toContainText(ORIGINAL_SPONSOR_WEBSITE);

    await originalRow.getByRole("button", { name: `Edit sponsor: ${ORIGINAL_SPONSOR_NAME}` }).click();

    await expect(dashboardContent.getByText("Sponsor Details", { exact: true })).toBeVisible();
    await organizerGroupPage.getByLabel("Name").fill(UPDATED_SPONSOR_NAME);
    await organizerGroupPage.getByLabel("Website").fill(UPDATED_SPONSOR_WEBSITE);

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response.url().includes(`/dashboard/group/sponsors/${TECH_CORP_SPONSOR_ID}/update`) &&
          response.ok(),
      ),
      organizerGroupPage.getByRole("button", { name: "Update Sponsor" }).click(),
    ]);

    const updatedRow = dashboardContent.locator("tr", { hasText: UPDATED_SPONSOR_NAME });
    await expect(updatedRow).toBeVisible();
    await expect(updatedRow).toContainText(UPDATED_SPONSOR_WEBSITE);

    await updatedRow.getByRole("button", { name: `Edit sponsor: ${UPDATED_SPONSOR_NAME}` }).click();

    await expect(dashboardContent.getByText("Sponsor Details", { exact: true })).toBeVisible();
    await organizerGroupPage.getByLabel("Name").fill(ORIGINAL_SPONSOR_NAME);
    await organizerGroupPage.getByLabel("Website").fill(ORIGINAL_SPONSOR_WEBSITE);

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response.url().includes(`/dashboard/group/sponsors/${TECH_CORP_SPONSOR_ID}/update`) &&
          response.ok(),
      ),
      organizerGroupPage.getByRole("button", { name: "Update Sponsor" }).click(),
    ]);

    const restoredRow = dashboardContent.locator("tr", { hasText: ORIGINAL_SPONSOR_NAME });
    await expect(restoredRow).toBeVisible();
    await expect(restoredRow).toContainText(ORIGINAL_SPONSOR_WEBSITE);
  });
});
