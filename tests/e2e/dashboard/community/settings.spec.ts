import { expect, test } from "../../fixtures";

import { navigateToPath } from "../../utils";

test.describe("community dashboard settings tab", () => {
  test("admin can update and restore community settings", async ({
    adminCommunityPage,
  }) => {
    const updatedDisplayName = `Platform Engineering Community ${Date.now()}`;
    const settingsPath = "/dashboard/community?tab=settings";

    const readSettingsFormValues = async () => {
      await navigateToPath(adminCommunityPage, settingsPath);

      const displayNameInput = adminCommunityPage.getByLabel("Display Name");
      const websiteInput = adminCommunityPage.getByLabel("Website");

      await expect(displayNameInput).toBeVisible();

      return {
        displayName: await displayNameInput.inputValue(),
        websiteUrl: await websiteInput.inputValue(),
      };
    };

    const submitSettings = async (displayName: string, websiteUrl: string) => {
      await navigateToPath(adminCommunityPage, settingsPath);

      await adminCommunityPage.getByLabel("Display Name").fill(displayName);
      await adminCommunityPage.getByLabel("Website").fill(websiteUrl);

      await Promise.all([
        adminCommunityPage.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response.url().includes("/dashboard/community/settings/update") &&
            response.ok(),
        ),
        adminCommunityPage.getByRole("button", { name: "Update Settings" }).click(),
      ]);

      await expect(adminCommunityPage.getByLabel("Display Name")).toHaveValue(displayName);
      await expect(adminCommunityPage.getByLabel("Website")).toHaveValue(websiteUrl);
    };

    const originalValues = await readSettingsFormValues();

    await submitSettings(updatedDisplayName, "https://community-e2e.example.com");
    await submitSettings(originalValues.displayName, originalValues.websiteUrl);
  });

  test("viewer sees read-only controls on community settings", async ({
    communityViewerPage,
  }) => {
    await navigateToPath(communityViewerPage, "/dashboard/community?tab=settings");

    const dashboardContent = communityViewerPage.locator("#dashboard-content");
    await expect(
      dashboardContent.getByText("General Settings", { exact: true }),
    ).toBeVisible();
    await expect(
      dashboardContent.getByText("Your role cannot update community settings.", {
        exact: true,
      }),
    ).toBeVisible();
    await expect(dashboardContent.locator(".inert-form")).toHaveAttribute("inert", "");
    await expect(
      dashboardContent.getByRole("button", { name: "Update Settings" }),
    ).toBeDisabled();
    await expect(
      dashboardContent.getByRole("button", { name: "Update Settings" }),
    ).toHaveAttribute("title", "Your role cannot update community settings.");
  });
});
