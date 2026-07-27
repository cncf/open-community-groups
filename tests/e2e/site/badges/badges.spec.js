import { expect, test } from "../../fixtures.js";

import { TEST_GROUP_IDS, buildE2eUrl, navigateToPath } from "../../utils.js";

const ACTIVE_CREDENTIAL_ID = "dadadada-dada-dada-dada-dadadadada02";
const BADGE_STATUS_LIST_ID = "cacacaca-caca-caca-caca-cacacacaca01";
const MEMBER_HOST_CREDENTIAL_ID = "dadadada-dada-dada-dada-dadadadada06";
const REVOKED_CREDENTIAL_ID = "dadadada-dada-dada-dada-dadadadada04";

test.describe("public badges", () => {
  test("credential pages expose active and revoked state without account identifiers", async ({ page }) => {
    // Check an active public credential.
    await navigateToPath(page, `/badges/credentials/${ACTIVE_CREDENTIAL_ID}`);
    await expect(page.getByRole("heading", { name: "Host" })).toBeVisible();
    await expect(page.getByText("Active credential", { exact: true })).toBeVisible();
    await expect(
      page.getByText("Platform Ops Meetup (Platform Engineering Community)", { exact: true }),
    ).toBeVisible();

    // Verify portable account identifiers are absent from the public page.
    await expect(page.locator("body")).not.toContainText("e2e-organizer-1@example.com");
    await expect(page.locator("body")).not.toContainText("e2e-organizer-1");

    // Check a previously revoked credential remains public history.
    await navigateToPath(page, `/badges/credentials/${REVOKED_CREDENTIAL_ID}`);
    await expect(page.getByRole("heading", { name: "Speaker" })).toBeVisible();
    await expect(page.getByText("Permanently revoked", { exact: true })).toBeVisible();
  });

  test("publishes credential, issuer, and status-list JSON contracts", async ({ request }) => {
    // Request the signed credential representation.
    const credentialResponse = await request.get(buildE2eUrl(`/badges/credentials/${ACTIVE_CREDENTIAL_ID}`), {
      headers: { Accept: "application/vc+ld+json" },
    });
    const credential = await credentialResponse.json();

    expect(credentialResponse.ok()).toBeTruthy();
    expect(credentialResponse.headers()["content-type"]).toContain("application/vc+ld+json");
    expect(credential.id).toBe(buildE2eUrl(`/badges/credentials/${ACTIVE_CREDENTIAL_ID}`));
    expect(credential.credentialSubject.id).toBe(`urn:uuid:${ACTIVE_CREDENTIAL_ID}`);
    expect(JSON.stringify(credential)).not.toContain("e2e-organizer-1");
    expect(JSON.stringify(credential)).not.toContain("@example.com");

    // Verify the referenced issuer publishes its assertion methods.
    const issuerResponse = await request.get(
      buildE2eUrl(`/badges/issuers/${TEST_GROUP_IDS.community1.alpha}`),
    );
    const issuer = await issuerResponse.json();

    expect(issuerResponse.ok()).toBeTruthy();
    expect(issuer.id).toBe(buildE2eUrl(`/badges/issuers/${TEST_GROUP_IDS.community1.alpha}`));
    expect(issuer.assertionMethod).not.toHaveLength(0);
    expect(issuer.verificationMethod).not.toHaveLength(0);

    // Verify the referenced status list is a signed credential.
    const statusResponse = await request.get(buildE2eUrl(`/badges/status-lists/${BADGE_STATUS_LIST_ID}`));
    const statusList = await statusResponse.json();

    expect(statusResponse.ok()).toBeTruthy();
    expect(statusResponse.headers()["content-type"]).toContain("application/vc+ld+json");
    expect(statusList.id).toBe(buildE2eUrl(`/badges/status-lists/${BADGE_STATUS_LIST_ID}`));
    expect(statusList.proof).toBeDefined();
  });

  test("verifies active and revoked credential references", async ({ page }) => {
    // Submit an active opaque credential ID through the browser form.
    await navigateToPath(page, "/badges/verify");
    await page.getByLabel("Credential URL or ID").fill(ACTIVE_CREDENTIAL_ID);
    await page.getByRole("button", { name: "Verify badge" }).click();

    await expect(page.getByText("Valid and active", { exact: true })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Host" })).toBeVisible();

    // Submit a revoked credential using its full public URL.
    await navigateToPath(page, "/badges/verify");
    await page
      .getByLabel("Credential URL or ID")
      .fill(buildE2eUrl(`/badges/credentials/${REVOKED_CREDENTIAL_ID}`));
    await page.getByRole("button", { name: "Verify badge" }).click();

    await expect(page.getByText("Credential revoked", { exact: true })).toBeVisible();
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
    await member1Page.locator('image-field[name="png"] input[type="file"]').setInputFiles({
      name: "host-open-badge.png",
      mimeType: "image/png",
      buffer: png,
    });
    await member1Page.getByRole("button", { name: "Verify badge" }).click();

    await expect(member1Page.getByText("Valid and active", { exact: true })).toBeVisible();
    await expect(member1Page.getByRole("heading", { name: "Host" })).toBeVisible();
  });

  test("rejects an invalid credential reference", async ({ page }) => {
    // Submit a non-local credential reference.
    await navigateToPath(page, "/badges/verify");
    await page.getByLabel("Credential URL or ID").fill("https://credentials.example.test/not-an-ocg-badge");
    await page.getByRole("button", { name: "Verify badge" }).click();

    await expect(page.getByRole("alert")).toContainText(
      "This badge could not be verified as an OCG-issued credential.",
    );
  });
});
