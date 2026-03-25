import { expect, test } from "../../fixtures";

import { navigateToPath } from "../../utils";

test.describe("group dashboard settings tab", () => {
  test("organizer can update and restore group settings", async ({
    organizerGroupPage,
  }) => {
    const settingsPath = "/dashboard/group?tab=settings";

    const readSettingsFormValues = async () => {
      await navigateToPath(organizerGroupPage, settingsPath);

      const settingsForm = organizerGroupPage.locator("#groups-form");
      await expect(settingsForm).toBeVisible();

      const descriptionEditor = organizerGroupPage.locator("markdown-editor#description");
      const description =
        (await descriptionEditor.getAttribute("content")) ??
        (await descriptionEditor.locator('textarea[name="description"]').first().inputValue());
      const regionId = await organizerGroupPage.locator("#region_id").inputValue();

      return {
        categoryId: await organizerGroupPage.locator("#category_id").inputValue(),
        description,
        name: await organizerGroupPage.locator("#name").inputValue(),
        regionId,
        websiteUrl: await organizerGroupPage.locator("#website_url").inputValue(),
      };
    };

    const submitSettings = async ({
      name,
      websiteUrl,
    }: {
      name: string;
      websiteUrl: string;
    }) => {
      await navigateToPath(organizerGroupPage, settingsPath);
      await organizerGroupPage.locator("#name").fill(name);
      await organizerGroupPage.locator("#website_url").fill(websiteUrl);

      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response.url().includes("/dashboard/group/settings/update") &&
            response.ok(),
        ),
        organizerGroupPage.getByRole("button", { name: "Update Group" }).click(),
      ]);
    };

    const originalFormValues = await readSettingsFormValues();
    test.skip(
      originalFormValues.description.trim() === "",
      "Requires a seeded non-empty group description for a round-trip update.",
    );
    const updatedName = `${originalFormValues.name} Updated`;
    const updatedWebsiteUrl = "https://group-e2e.example.com";

    await submitSettings({
      name: updatedName,
      websiteUrl: updatedWebsiteUrl,
    });

    await expect(organizerGroupPage.locator("#name")).toHaveValue(updatedName);
    await expect(organizerGroupPage.locator("#website_url")).toHaveValue(updatedWebsiteUrl);

    await submitSettings(originalFormValues);

    await expect(organizerGroupPage.locator("#name")).toHaveValue(originalFormValues.name);
    await expect(organizerGroupPage.locator("#website_url")).toHaveValue(
      originalFormValues.websiteUrl,
    );
  });

  test("viewer sees read-only controls on group settings", async ({
    groupViewerPage,
  }) => {
    await navigateToPath(groupViewerPage, "/dashboard/group?tab=settings");

    const dashboardContent = groupViewerPage.locator("#dashboard-content");
    await expect(dashboardContent.getByText("Group Details", { exact: true })).toBeVisible();
    await expect(
      dashboardContent.getByText("Your role cannot update group settings.", { exact: true }),
    ).toBeVisible();
    await expect(dashboardContent.locator(".inert-form")).toHaveAttribute("inert", "");
    await expect(
      dashboardContent.getByRole("button", { name: "Update Group" }),
    ).toBeDisabled();
    await expect(
      dashboardContent.getByRole("button", { name: "Update Group" }),
    ).toHaveAttribute("title", "Your role cannot update group settings.");
  });
});
