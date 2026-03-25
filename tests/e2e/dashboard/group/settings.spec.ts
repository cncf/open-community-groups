import { expect, test } from "../../fixtures";

import { fillMarkdownEditor } from "../form-helpers";
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
      categoryId,
      description,
      name,
      regionId,
      websiteUrl,
    }: {
      categoryId: string;
      description: string;
      name: string;
      regionId: string;
      websiteUrl: string;
    }) => {
      await navigateToPath(organizerGroupPage, settingsPath);
      await organizerGroupPage.locator("#category_id").selectOption(categoryId);
      await organizerGroupPage.locator("#region_id").selectOption(regionId);
      await organizerGroupPage.locator("#name").fill(name);
      await fillMarkdownEditor(organizerGroupPage, "description", description);
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
    const updatedValues = {
      ...originalFormValues,
      categoryId:
        originalFormValues.categoryId === "22222222-2222-2222-2222-222222222221"
          ? "22222222-2222-2222-2222-222222222223"
          : "22222222-2222-2222-2222-222222222221",
      description: "Updated primary meetup details for group settings coverage.",
      name: `${originalFormValues.name} Updated`,
      regionId:
        originalFormValues.regionId === "22222222-2222-2222-2222-222222222301"
          ? "22222222-2222-2222-2222-222222222302"
          : "22222222-2222-2222-2222-222222222301",
    };

    await submitSettings(updatedValues);

    await expect(organizerGroupPage.locator("#category_id")).toHaveValue(updatedValues.categoryId);
    await expect(organizerGroupPage.locator("#region_id")).toHaveValue(updatedValues.regionId);
    await expect(organizerGroupPage.locator("#name")).toHaveValue(updatedValues.name);
    await expect(organizerGroupPage.locator("markdown-editor#description")).toHaveAttribute(
      "content",
      updatedValues.description,
    );
    await expect(organizerGroupPage.locator("#website_url")).toHaveValue(
      updatedValues.websiteUrl,
    );

    await submitSettings(originalFormValues);

    await expect(organizerGroupPage.locator("#category_id")).toHaveValue(
      originalFormValues.categoryId,
    );
    await expect(organizerGroupPage.locator("#region_id")).toHaveValue(originalFormValues.regionId);
    await expect(organizerGroupPage.locator("#name")).toHaveValue(originalFormValues.name);
    await expect(organizerGroupPage.locator("markdown-editor#description")).toHaveAttribute(
      "content",
      originalFormValues.description,
    );
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
