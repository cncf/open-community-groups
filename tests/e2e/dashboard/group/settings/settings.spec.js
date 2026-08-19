import { expect, test } from "../../../fixtures.js";

import { fillMarkdownEditor } from "../../form-helpers.js";
import {
  navigateToPath,
  TEST_PAYMENT_GROUP_RECIPIENT,
  waitForActionResponse,
} from "../../../utils.js";

test.describe("group dashboard settings view", () => {
  test("settings form exposes every group configuration area", async ({
    organizerGroupPage,
  }) => {
    // Load group settings before checking the complete form contract.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=settings");

    // Find the dashboard and verify every settings section is present.
    const dashboardContent = organizerGroupPage.locator("#dashboard-content");
    for (const sectionName of [
      "Group Details",
      "Location",
      "Social links",
      "Additional Content",
      "Parent group",
    ]) {
      // Some section titles are repeated by field labels, so target the first.
      await expect(
        dashboardContent.getByText(sectionName, { exact: true }).first(),
      ).toBeVisible();
    }

    // Verify required controls, slug rules, and location fields.
    await expect(organizerGroupPage.locator("#name")).toHaveAttribute(
      "required",
      "",
    );
    await expect(
      organizerGroupPage.getByLabel("Pretty URL slug"),
    ).toHaveAttribute(
      "pattern",
      "(?!.*--)[a-z0-9](?:[a-z0-9-]{0,48}[a-z0-9])?",
    );
    await expect(organizerGroupPage.getByLabel("Category")).toHaveAttribute(
      "required",
      "",
    );
    await expect(organizerGroupPage.getByLabel("Region")).toBeVisible();
    await expect(
      organizerGroupPage.getByLabel("Short Description"),
    ).toBeVisible();
    await expect(
      organizerGroupPage.locator("markdown-editor#description"),
    ).toHaveAttribute("required", "");

    // Verify every group image field is available.
    for (const imageFieldName of [
      "logo_url",
      "banner_url",
      "banner_mobile_url",
      "og_image_url",
    ]) {
      await expect(
        organizerGroupPage.locator(`image-field[name="${imageFieldName}"]`),
      ).toBeVisible();
    }

    await expect(
      organizerGroupPage.locator("location-search-field#group-location-search"),
    ).toBeVisible();
    await expect(
      organizerGroupPage.getByRole("button", {
        name: "Clear location details",
      }),
    ).toBeVisible();

    // Verify every social destination uses a URL input.
    for (const socialLabel of [
      "Website",
      "Bluesky",
      "Facebook",
      "Flickr",
      "GitHub",
      "Instagram",
      "LinkedIn",
      "Slack",
      "X (formerly Twitter)",
      "WeChat",
      "YouTube",
    ]) {
      await expect(organizerGroupPage.getByLabel(socialLabel)).toHaveAttribute(
        "type",
        "url",
      );
    }

    // Verify the remaining repeatable fields and parent-group restriction.
    await expect(
      organizerGroupPage.locator('multiple-inputs[field-name="tags"]'),
    ).toBeVisible();
    await expect(
      organizerGroupPage.locator('gallery-field[field-name="photos_urls"]'),
    ).toBeVisible();
    await expect(
      organizerGroupPage.locator('key-value-inputs[field-name="extra_links"]'),
    ).toBeVisible();
    await expect(organizerGroupPage.getByLabel("Parent group")).toBeDisabled();
  });

  test("invalid pretty slugs are blocked before the group settings request", async ({
    organizerGroupPage,
  }) => {
    // Load group settings before submitting an invalid slug.
    await navigateToPath(organizerGroupPage, "/dashboard/group?tab=settings");

    // Track update requests so browser validation can be distinguished from API errors.
    const prettySlugInput = organizerGroupPage.getByLabel("Pretty URL slug");
    let updateRequests = 0;
    const countUpdateRequests = (request) => {
      if (
        request.method() === "PUT" &&
        request.url().includes("/dashboard/group/settings/update")
      ) {
        updateRequests += 1;
      }
    };
    organizerGroupPage.on("request", countUpdateRequests);

    // Submit a slug that violates the field pattern.
    await prettySlugInput.fill("Invalid Group Slug");
    await organizerGroupPage
      .getByRole("button", { name: "Update Group" })
      .click();

    // Verify the browser blocks the request and focuses the invalid field.
    await expect(prettySlugInput).toBeFocused();
    expect(
      await prettySlugInput.evaluate((input) => input.validationMessage),
    ).not.toBe("");
    expect(updateRequests).toBe(0);

    organizerGroupPage.off("request", countUpdateRequests);
  });

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
      await waitForActionResponse(
        organizerGroupPage,
        () =>
          organizerGroupPage
            .getByRole("button", { name: "Update Group" })
            .click(),
        {
          method: "PUT",
          urlIncludes: "/dashboard/group/settings/update",
        },
      );
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

    // Find the fiscal sponsor inputs.
    const sellerDisplayNameInput = dashboardContent.locator(
      "#payment_recipient_seller_display_name",
    );
    const paymentRecipientInput = dashboardContent.locator(
      "#payment_recipient_recipient_id",
    );

    // Verify the complete fiscal sponsor configuration when payments are enabled.
    if ((await paymentRecipientInput.count()) > 0) {
      await expect(sellerDisplayNameInput).toHaveValue(
        "E2E Alpha Fiscal Sponsor",
      );
      await expect(paymentRecipientInput).toHaveValue(
        TEST_PAYMENT_GROUP_RECIPIENT,
      );
      return;
    }

    // Assert how many matching elements are shown.
    await expect(paymentRecipientInput).toHaveCount(0);
  });

  test("validates fiscal sponsor field pairs without contacting the provider", async ({
    organizerGroupPage,
    organizerGroupWithoutPaymentsPage,
  }) => {
    // Define the settings URL and fiscal sponsor fields used by the scenario.
    const settingsPath = "/dashboard/group?tab=settings";
    const sellerDisplayNameInput = organizerGroupWithoutPaymentsPage.locator(
      "#payment_recipient_seller_display_name",
    );
    const paymentRecipientInput = organizerGroupWithoutPaymentsPage.locator(
      "#payment_recipient_recipient_id",
    );
    const updatedSellerDisplayName = "E2E Delta Fiscal Sponsor";
    const updatedRecipient = "acct_e2e_delta";

    // Open the settings page for a group without a fiscal sponsor.
    await navigateToPath(organizerGroupWithoutPaymentsPage, settingsPath);
    test.skip(
      (await paymentRecipientInput.count()) === 0,
      "Payments are disabled in this environment.",
    );
    await expect(
      organizerGroupWithoutPaymentsPage.getByText("Fiscal Sponsor", {
        exact: true,
      }),
    ).toBeVisible();
    await expect(sellerDisplayNameInput).toHaveValue("");
    await expect(paymentRecipientInput).toHaveValue("");
    const updateGroupButton = organizerGroupWithoutPaymentsPage.getByRole(
      "button",
      { name: "Update Group" },
    );
    const settingsUpdateRequests = [];
    const collectSettingsUpdateRequest = (request) => {
      if (
        request.method() === "PUT" &&
        request.url().includes("/dashboard/group/settings/update")
      ) {
        settingsUpdateRequests.push(request);
      }
    };
    organizerGroupWithoutPaymentsPage.on(
      "request",
      collectSettingsUpdateRequest,
    );

    // Reject a legal seller name without its paired provider account.
    await sellerDisplayNameInput.fill(updatedSellerDisplayName);
    await expect(sellerDisplayNameInput).toHaveAttribute("required", "");
    await expect(paymentRecipientInput).toHaveAttribute("required", "");
    await expect
      .poll(() =>
        paymentRecipientInput.evaluate((input) => input.validity.valueMissing),
      )
      .toBe(true);
    await updateGroupButton.click();
    expect(settingsUpdateRequests).toHaveLength(0);

    // Reject a provider account without its paired legal seller name.
    await navigateToPath(organizerGroupWithoutPaymentsPage, settingsPath);
    await paymentRecipientInput.fill(updatedRecipient);
    await expect(sellerDisplayNameInput).toHaveAttribute("required", "");
    await expect(paymentRecipientInput).toHaveAttribute("required", "");
    await expect
      .poll(() =>
        sellerDisplayNameInput.evaluate((input) => input.validity.valueMissing),
      )
      .toBe(true);
    await updateGroupButton.click();
    expect(settingsUpdateRequests).toHaveLength(0);
    organizerGroupWithoutPaymentsPage.off(
      "request",
      collectSettingsUpdateRequest,
    );

    // Accept an empty pair without invoking provider readiness.
    await navigateToPath(organizerGroupWithoutPaymentsPage, settingsPath);
    await waitForActionResponse(
      organizerGroupWithoutPaymentsPage,
      () => updateGroupButton.click(),
      {
        method: "PUT",
        urlIncludes: "/dashboard/group/settings/update",
      },
    );
    await expect(sellerDisplayNameInput).toHaveValue("");
    await expect(paymentRecipientInput).toHaveValue("");

    // Accept an unchanged complete pair without invoking provider readiness.
    await navigateToPath(organizerGroupPage, settingsPath);
    const configuredSellerDisplayNameInput = organizerGroupPage.locator(
      "#payment_recipient_seller_display_name",
    );
    const configuredRecipientInput = organizerGroupPage.locator(
      "#payment_recipient_recipient_id",
    );
    await expect(configuredSellerDisplayNameInput).toHaveValue(
      "E2E Alpha Fiscal Sponsor",
    );
    await expect(configuredRecipientInput).toHaveValue(
      TEST_PAYMENT_GROUP_RECIPIENT,
    );
    await waitForActionResponse(
      organizerGroupPage,
      () =>
        organizerGroupPage
          .getByRole("button", { name: "Update Group" })
          .click(),
      {
        method: "PUT",
        urlIncludes: "/dashboard/group/settings/update",
      },
    );
    await expect(configuredSellerDisplayNameInput).toHaveValue(
      "E2E Alpha Fiscal Sponsor",
    );
    await expect(configuredRecipientInput).toHaveValue(
      TEST_PAYMENT_GROUP_RECIPIENT,
    );
  });
});
