import { expect, test } from "../../../fixtures.js";

import { fillMarkdownEditor } from "../../form-helpers.js";
import {
  navigateToPath,
  TEST_PAYMENT_GROUP_RECIPIENT,
} from "../../../utils.js";

test.describe("group dashboard settings view", () => {
  test("organizer can update and restore group settings", async ({
    organizerGroupPage,
  }) => {
    // Define the settings URL used by the read and submit helpers.
    const settingsPath = "/dashboard/group?tab=settings";

    // Read current group settings values before updating them.
    const readSettingsFormValues = async () => {
      await navigateToPath(organizerGroupPage, settingsPath);

      // Find the settings form.
      const settingsForm = organizerGroupPage.locator("#groups-form");
      await expect(settingsForm).toBeVisible();

      // Find the description editor.
      const descriptionEditor = organizerGroupPage.locator(
        "markdown-editor#description",
      );
      const description =
        (await descriptionEditor.getAttribute("content")) ??
        (await descriptionEditor
          .locator('textarea[name="description"]')
          .first()
          .inputValue());
      const regionId = await organizerGroupPage
        .locator("#region_id")
        .inputValue();

      // Return the values used by the caller.
      return {
        categoryId: await organizerGroupPage
          .locator("#category_id")
          .inputValue(),
        description,
        name: await organizerGroupPage.locator("#name").inputValue(),
        regionId,
        websiteUrl: await organizerGroupPage
          .locator("#website_url")
          .inputValue(),
      };
    };

    // Submit group settings values and wait for persistence.
    const submitSettings = async ({
      categoryId,
      description,
      name,
      regionId,
      websiteUrl,
    }) => {
      await navigateToPath(organizerGroupPage, settingsPath);
      await organizerGroupPage.locator("#category_id").selectOption(categoryId);
      await organizerGroupPage.locator("#region_id").selectOption(regionId);
      await organizerGroupPage.locator("#name").fill(name);
      await fillMarkdownEditor(organizerGroupPage, "description", description);
      await organizerGroupPage.locator("#website_url").fill(websiteUrl);

      // Click Update Group.
      await Promise.all([
        organizerGroupPage.waitForResponse(
          (response) =>
            response.request().method() === "PUT" &&
            response.url().includes("/dashboard/group/settings/update") &&
            response.ok(),
        ),
        organizerGroupPage
          .getByRole("button", { name: "Update Group" })
          .click(),
      ]);
    };

    // Set up original form values.
    const originalFormValues = await readSettingsFormValues();
    const updatedValues = {
      ...originalFormValues,
      categoryId: originalFormValues.categoryId,
      description:
        "Updated primary meetup details for group settings coverage.",
      name: `${originalFormValues.name} Updated`,
      regionId: originalFormValues.regionId,
    };

    // Save the updated settings.
    await submitSettings(updatedValues);

    // Assert the field value was updated.
    await expect(organizerGroupPage.locator("#category_id")).toHaveValue(
      updatedValues.categoryId,
    );
    await expect(organizerGroupPage.locator("#region_id")).toHaveValue(
      updatedValues.regionId,
    );
    await expect(organizerGroupPage.locator("#name")).toHaveValue(
      updatedValues.name,
    );
    await expect(
      organizerGroupPage.locator("markdown-editor#description"),
    ).toHaveAttribute("content", updatedValues.description);
    await expect(organizerGroupPage.locator("#website_url")).toHaveValue(
      updatedValues.websiteUrl,
    );

    // Restore the original settings.
    await submitSettings(originalFormValues);

    // Assert the field value was updated.
    await expect(organizerGroupPage.locator("#category_id")).toHaveValue(
      originalFormValues.categoryId,
    );
    await expect(organizerGroupPage.locator("#region_id")).toHaveValue(
      originalFormValues.regionId,
    );
    await expect(organizerGroupPage.locator("#name")).toHaveValue(
      originalFormValues.name,
    );
    await expect(
      organizerGroupPage.locator("markdown-editor#description"),
    ).toHaveAttribute("content", originalFormValues.description);
    await expect(organizerGroupPage.locator("#website_url")).toHaveValue(
      originalFormValues.websiteUrl,
    );
  });

  test("viewer sees read-only controls on group settings", async ({
    groupViewerPage,
  }) => {
    // Load the group settings tab as a read-only viewer.
    await navigateToPath(groupViewerPage, "/dashboard/group?tab=settings");

    // Find the dashboard content.
    const dashboardContent = groupViewerPage.locator("#dashboard-content");

    // Verify viewer sees read-only controls on group settings.
    await expect(
      dashboardContent.getByText("Group Details", { exact: true }),
    ).toBeVisible();
    await expect(
      dashboardContent.getByText("Your role cannot update group settings.", {
        exact: true,
      }),
    ).toBeVisible();
    await expect(dashboardContent.locator(".inert-form")).toHaveAttribute(
      "inert",
      "",
    );
    const updateGroupButton = dashboardContent.getByRole("button", {
      name: "Update Group",
    });

    // Dismiss pending group-setting changes when the button is present.
    if ((await updateGroupButton.count()) > 0) {
      await expect(updateGroupButton).toBeDisabled();
      await expect(updateGroupButton).toHaveAttribute(
        "title",
        "Your role cannot update group settings.",
      );
    }

    // Find the payment recipient input.
    const paymentRecipientInput = dashboardContent.locator(
      "#payment_recipient_recipient_id",
    );

    // Clear the payment recipient when the field is present.
    if ((await paymentRecipientInput.count()) > 0) {
      await expect(paymentRecipientInput).toHaveValue(
        TEST_PAYMENT_GROUP_RECIPIENT,
      );
      return;
    }

    // Assert how many matching elements are shown.
    await expect(paymentRecipientInput).toHaveCount(0);
  });

  test("organizer can set and clear the Stripe recipient", async ({
    organizerGroupWithoutPaymentsPage,
  }) => {
    // Define the settings URL and payment field used by the scenario.
    const settingsPath = "/dashboard/group?tab=settings";
    const paymentRecipientInput = organizerGroupWithoutPaymentsPage.locator(
      "#payment_recipient_recipient_id",
    );
    const updatedRecipient = "  acct_e2e_delta  ";

    // Open the group settings page.
    await navigateToPath(organizerGroupWithoutPaymentsPage, settingsPath);
    test.skip(
      (await paymentRecipientInput.count()) === 0,
      "Payments are disabled in this environment.",
    );

    // Verify the group starts without a Stripe recipient.
    await expect(
      organizerGroupWithoutPaymentsPage.getByText("Payments", { exact: true }),
    ).toBeVisible();
    await expect(paymentRecipientInput).toHaveValue("");

    // Fill the form field.
    await paymentRecipientInput.fill(updatedRecipient);

    // Click Update Group.
    await Promise.all([
      organizerGroupWithoutPaymentsPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response.url().includes("/dashboard/group/settings/update") &&
          response.ok(),
      ),
      organizerGroupWithoutPaymentsPage
        .getByRole("button", { name: "Update Group" })
        .click(),
    ]);

    // Assert the field value was updated.
    await expect(paymentRecipientInput).toHaveValue("acct_e2e_delta");

    // Clear the form field.
    await paymentRecipientInput.fill("");

    // Click Update Group.
    await Promise.all([
      organizerGroupWithoutPaymentsPage.waitForResponse(
        (response) =>
          response.request().method() === "PUT" &&
          response.url().includes("/dashboard/group/settings/update") &&
          response.ok(),
      ),
      organizerGroupWithoutPaymentsPage
        .getByRole("button", { name: "Update Group" })
        .click(),
    ]);

    // Assert the field value was cleared.
    await expect(paymentRecipientInput).toHaveValue("");
  });
});
