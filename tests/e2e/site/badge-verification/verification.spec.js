import { expect, test } from "../../fixtures.js";

import { TEST_GROUP_IDS, buildE2eUrl, navigateToPath } from "../../utils.js";

const ACTIVE_CREDENTIAL_ID = "dadadada-dada-dada-dada-dadadadada02";
const BADGE_STATUS_LIST_ID = "cacacaca-caca-caca-caca-cacacacaca01";
const MEMBER_HOST_CREDENTIAL_ID = "dadadada-dada-dada-dada-dadadadada06";
const REVOKED_CREDENTIAL_ID = "dadadada-dada-dada-dada-dadadadada04";

test.describe("public badge verification page", () => {
  test("verification form explains both supported inputs and empty failures", async ({
    page,
  }) => {
    // Load the public badge verification form.
    await navigateToPath(page, "/badges/verify");

    // Verify the form explains reference and PNG verification inputs.
    await expect(
      page.getByRole("heading", { name: "Verify an OCG badge" }),
    ).toBeVisible();
    await expect(
      page.getByText(
        "Enter an OCG credential URL or ID, or upload an exported PNG.",
        { exact: true },
      ),
    ).toBeVisible();
    await expect(page.getByLabel("Credential URL or ID")).toHaveAttribute(
      "autocomplete",
      "off",
    );
    await expect(page.locator('image-field[name="png"]')).toHaveAttribute(
      "accepted-formats",
      "image/png",
    );

    // Submit an empty form and verify the accessible failure state.
    await page.getByRole("button", { name: "Verify badge" }).click();
    await expect(page.getByRole("alert")).toContainText(
      "This badge could not be verified as an OCG-issued credential.",
    );
  });

  test("verifies active and revoked credential references", async ({
    page,
  }) => {
    // Submit an active opaque credential ID through the browser form.
    await navigateToPath(page, "/badges/verify");
    await page.getByLabel("Credential URL or ID").fill(ACTIVE_CREDENTIAL_ID);
    await page.getByRole("button", { name: "Verify badge" }).click();

    await expect(
      page.getByText("Valid and active", { exact: true }),
    ).toBeVisible();
    await expect(page.getByRole("heading", { name: "Host" })).toBeVisible();

    // Submit a revoked credential using its full public URL.
    await navigateToPath(page, "/badges/verify");
    await page
      .getByLabel("Credential URL or ID")
      .fill(buildE2eUrl(`/badges/credentials/${REVOKED_CREDENTIAL_ID}`));
    await page.getByRole("button", { name: "Verify badge" }).click();

    await expect(
      page.getByText("Credential revoked", { exact: true }),
    ).toBeVisible();
    await expect(page.getByRole("heading", { name: "Speaker" })).toBeVisible();
  });

  test("verifies an authenticated exported PNG", async ({ member1Page }) => {
    // Export a signed PNG without writing a temporary project file.
    const exportResponse = await member1Page.request.get(
      buildE2eUrl(`/dashboard/user/badges/${MEMBER_HOST_CREDENTIAL_ID}/export`),
    );
    const png = await exportResponse.body();

    expect(exportResponse.ok()).toBeTruthy();

    // Upload the exported bytes through the public verification form.
    await navigateToPath(member1Page, "/badges/verify");
    await member1Page
      .locator('image-field[name="png"] input[type="file"]')
      .setInputFiles({
        name: "host-open-badge.png",
        mimeType: "image/png",
        buffer: png,
      });
    await member1Page.getByRole("button", { name: "Verify badge" }).click();

    await expect(
      member1Page.getByText("Valid and active", { exact: true }),
    ).toBeVisible();
    await expect(
      member1Page.getByRole("heading", { name: "Host" }),
    ).toBeVisible();
  });

  test("rejects an invalid credential reference", async ({ page }) => {
    // Submit a non-local credential reference.
    await navigateToPath(page, "/badges/verify");
    await page
      .getByLabel("Credential URL or ID")
      .fill("https://credentials.example.test/not-an-ocg-badge");
    await page.getByRole("button", { name: "Verify badge" }).click();

    await expect(page.getByRole("alert")).toContainText(
      "This badge could not be verified as an OCG-issued credential.",
    );
  });

  test("rejects corrupt, unbaked, and oversized PNG credentials", async ({
    page,
  }) => {
    // Upload bytes labelled as PNG that do not contain a valid image.
    await navigateToPath(page, "/badges/verify");
    const pngInput = page.locator('image-field[name="png"] input[type="file"]');
    await pngInput.setInputFiles({
      name: "corrupt-open-badge.png",
      mimeType: "image/png",
      buffer: Buffer.from("not a png credential"),
    });
    await page.getByRole("button", { name: "Verify badge" }).click();
    await expect(page.getByRole("alert")).toContainText(
      "This badge could not be verified as an OCG-issued credential.",
    );

    // Upload a valid site PNG that has no baked credential chunk.
    const ordinaryImageResponse = await page.request.get(
      buildE2eUrl("/static/images/e2e/badges/host.png"),
    );
    expect(ordinaryImageResponse.ok()).toBeTruthy();
    await navigateToPath(page, "/badges/verify");
    await page
      .locator('image-field[name="png"] input[type="file"]')
      .setInputFiles({
        name: "ordinary-preview.png",
        mimeType: "image/png",
        buffer: await ordinaryImageResponse.body(),
      });
    await page.getByRole("button", { name: "Verify badge" }).click();
    await expect(page.getByRole("alert")).toContainText(
      "This badge could not be verified as an OCG-issued credential.",
    );

    // Submit a payload beyond the bounded Open Badges PNG size and verify the
    // server refuses it with an error response or closes the upload stream.
    let oversizedResponse;
    let oversizedUploadError;
    try {
      oversizedResponse = await page.request.post(
        buildE2eUrl("/badges/verify"),
        {
          multipart: {
            credential: "",
            png: {
              name: "oversized-open-badge.png",
              mimeType: "image/png",
              buffer: Buffer.alloc(12 * 1024 * 1024 + 1),
            },
          },
        },
      );
    } catch (error) {
      oversizedUploadError = error;
    }

    if (oversizedResponse) {
      expect(oversizedResponse.status()).toBeGreaterThanOrEqual(400);
    } else {
      expect(String(oversizedUploadError)).toMatch(/\b(?:ECONNRESET|EPIPE)\b/u);
    }
  });
});
