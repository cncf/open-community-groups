import { expect, test } from "../../fixtures";

import { TEST_UPLOAD_ASSET_PATHS, setImageFieldValue, uploadImageField } from "../form-helpers";
import { navigateToPath } from "../../utils";

const TECH_CORP_SPONSOR_ID = "66666666-6666-6666-6666-666666666601";
const ORIGINAL_SPONSOR_NAME = "Tech Corp";
const UPDATED_SPONSOR_NAME = "Tech Corp Updated";
const ORIGINAL_SPONSOR_WEBSITE = "https://techcorp.example.com";
const UPDATED_SPONSOR_WEBSITE = "https://updated-techcorp.example.com";
const ORIGINAL_SPONSOR_LOGO_URL = "/static/images/e2e/sponsor-logo.svg";
const UPDATED_SPONSOR_LOGO_URL = "/static/images/e2e/community-secondary-logo.svg";

test.describe("group sponsors dashboard", () => {
  test("organizer can add and delete a sponsor", async ({
    organizerGroupPage,
  }) => {
    const sponsorName = `E2E Sponsor ${Date.now()}`;
    const sponsorWebsite = "https://e2e-sponsor.example.com";

    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=sponsors");

    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Sponsors", { exact: true })).toBeVisible();

    await organizerGroupPage.getByRole("button", { name: "Add Sponsor" }).click();
    await expect(dashboardContent.getByText("Sponsor Details", { exact: true })).toBeVisible();

    await organizerGroupPage.getByLabel("Name").fill(sponsorName);
    await organizerGroupPage.getByLabel("Website").fill(sponsorWebsite);

    await uploadImageField(organizerGroupPage, "logo_url", TEST_UPLOAD_ASSET_PATHS.logo);

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "POST" &&
          response.url().includes("/dashboard/group/sponsors/add") &&
          response.status() === 201,
      ),
      organizerGroupPage.getByRole("button", { name: "Add Sponsor" }).click(),
    ]);

    const sponsorRow = dashboardContent.locator("tr", { hasText: sponsorName });
    await expect(sponsorRow).toBeVisible();
    await expect(sponsorRow).toContainText(sponsorWebsite);

    await sponsorRow.getByRole("button", { name: `Delete sponsor: ${sponsorName}` }).click();
    await expect(organizerGroupPage.locator(".swal2-popup")).toContainText(
      "Are you sure you would like to delete this sponsor?",
    );

    await Promise.all([
      organizerGroupPage.waitForResponse(
        (response) =>
          response.request().method() === "DELETE" &&
          response.url().includes("/dashboard/group/sponsors/") &&
          response.ok(),
      ),
      organizerGroupPage.getByRole("button", { name: "Yes" }).click(),
    ]);

    await expect(dashboardContent.locator("tr", { hasText: sponsorName })).toHaveCount(0);
  });

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
    await setImageFieldValue(organizerGroupPage, "logo_url", UPDATED_SPONSOR_LOGO_URL);

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
    await expect(
      organizerGroupPage.locator('image-field[name="logo_url"] input[name="logo_url"]'),
    ).toHaveValue(UPDATED_SPONSOR_LOGO_URL);
    await organizerGroupPage.getByLabel("Name").fill(ORIGINAL_SPONSOR_NAME);
    await organizerGroupPage.getByLabel("Website").fill(ORIGINAL_SPONSOR_WEBSITE);
    await setImageFieldValue(organizerGroupPage, "logo_url", ORIGINAL_SPONSOR_LOGO_URL);

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

  test("viewer sees read-only controls on the sponsors page", async ({
    groupViewerPage,
  }) => {
    await navigateToPath(groupViewerPage, "/dashboard/group?tab=sponsors");

    const sponsorsContent = groupViewerPage.locator("#dashboard-content");
    await expect(sponsorsContent.getByText("Sponsors", { exact: true })).toBeVisible();
    await expect(
      sponsorsContent.getByRole("button", { name: "Add Sponsor" }),
    ).toBeDisabled();

    const sponsorRow = sponsorsContent.locator("tr", { hasText: "Tech Corp" });
    await expect(sponsorRow).toBeVisible();
    await expect(
      sponsorRow.getByRole("button", { name: "Delete sponsor: Tech Corp" }),
    ).toBeDisabled();
    await expect(
      sponsorRow.getByRole("button", { name: "Delete sponsor: Tech Corp" }),
    ).toHaveAttribute("title", "Your role cannot delete sponsors.");
  });
});
