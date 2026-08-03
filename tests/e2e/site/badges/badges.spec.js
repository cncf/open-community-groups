import { expect, test } from "../../fixtures.js";

import { TEST_GROUP_IDS, buildE2eUrl, navigateToPath } from "../../utils.js";

const ACTIVE_CREDENTIAL_ID = "dadadada-dada-dada-dada-dadadadada02";
const BADGE_STATUS_LIST_ID = "cacacaca-caca-caca-caca-cacacacaca01";
const MEMBER_HOST_CREDENTIAL_ID = "dadadada-dada-dada-dada-dadadadada06";
const REVOKED_CREDENTIAL_ID = "dadadada-dada-dada-dada-dadadadada04";

test.describe("public badges", () => {
  test("credential page exposes complete award copy and artwork", async ({ page }) => {
    // Load an active public badge credential.
    await navigateToPath(page, `/badges/credentials/${ACTIVE_CREDENTIAL_ID}`);

    // Verify its artwork, issuer metadata, award date, and criteria copy.
    await expect(page).toHaveTitle("Host badge");
    await expect(page.getByAltText("Host badge artwork")).toBeVisible();
    await expect(
      page.getByText("Recognizes contributors who host Platform Ops Meetup events.", { exact: true }),
    ).toBeVisible();
    await expect(page.getByText("Issued by", { exact: true })).toBeVisible();
    await expect(page.getByText("Awarded", { exact: true })).toBeVisible();
    // The award date is seeded relative to load time, so assert the format only.
    await expect(page.locator('dt:text-is("Awarded") + dd')).toHaveText(
      /^\s*\d{4}-\d{2}-\d{2}\s*$/,
    );
    await expect(page.getByText("Criteria", { exact: true })).toBeVisible();
    await expect(
      page.getByText("Serve as a host for a Platform Ops Meetup event.", {
        exact: true,
      }),
    ).toBeVisible();
  });

  test("verification form explains both supported inputs and empty failures", async ({ page }) => {
    // Load the public badge verification form.
    await navigateToPath(page, "/badges/verify");

    // Verify the form explains reference and PNG verification inputs.
    await expect(page.getByRole("heading", { name: "Verify an OCG badge" })).toBeVisible();
    await expect(
      page.getByText("Enter an OCG credential URL or ID, or upload an exported PNG.", { exact: true }),
    ).toBeVisible();
    await expect(page.getByLabel("Credential URL or ID")).toHaveAttribute("autocomplete", "off");
    await expect(page.locator('image-field[name="png"]')).toHaveAttribute("accepted-formats", "image/png");

    // Submit an empty form and verify the accessible failure state.
    await page.getByRole("button", { name: "Verify badge" }).click();
    await expect(page.getByRole("alert")).toContainText(
      "This badge could not be verified as an OCG-issued credential.",
    );
  });

  test("credential pages expose active and revoked state without account identifiers", async ({ page }) => {
    // Check an active public credential.
    await navigateToPath(page, `/badges/credentials/${ACTIVE_CREDENTIAL_ID}`);
    await expect(page.getByRole("heading", { name: "Host" })).toBeVisible();
    await expect(page.getByText("Active credential", { exact: true })).toBeVisible();
    await expect(
      page.getByText("Platform Ops Meetup (Platform Engineering Community)", {
        exact: true,
      }),
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

  test("publishes dereferenceable immutable issuer key JSON", async ({ request }) => {
    // Resolve one retained verification method from the public issuer profile.
    const issuerUrl = buildE2eUrl(`/badges/issuers/${TEST_GROUP_IDS.community1.alpha}`);
    const issuerResponse = await request.get(issuerUrl);
    const issuer = await issuerResponse.json();
    const verificationMethod = issuer.verificationMethod[0];
    const keyMultibase = verificationMethod.publicKeyMultibase;
    expect(issuerResponse.ok()).toBeTruthy();
    expect(keyMultibase).toMatch(/^z6Mk/u);

    // Dereference the content-addressed key and verify its complete Multikey contract.
    const keyUrl = `${issuerUrl}/keys/${keyMultibase}`;
    const keyResponse = await request.get(keyUrl);
    const key = await keyResponse.json();
    expect(keyResponse.ok()).toBeTruthy();
    expect(keyResponse.headers()["content-type"]).toContain("application/json");
    expect(keyResponse.headers()["cache-control"]).toBe("public, max-age=31536000, immutable");
    expect(key).toEqual({
      "@context": "https://w3id.org/security/multikey/v1",
      controller: issuerUrl,
      id: keyUrl,
      publicKeyMultibase: keyMultibase,
      type: "Multikey",
    });
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

  test("rejects corrupt, unbaked, and oversized PNG credentials", async ({ page }) => {
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
    await page.locator('image-field[name="png"] input[type="file"]').setInputFiles({
      name: "ordinary-preview.png",
      mimeType: "image/png",
      buffer: await ordinaryImageResponse.body(),
    });
    await page.getByRole("button", { name: "Verify badge" }).click();
    await expect(page.getByRole("alert")).toContainText(
      "This badge could not be verified as an OCG-issued credential.",
    );

    // Submit a payload beyond the bounded Open Badges PNG size and verify the
    // server refuses it with an error status instead of verifying the badge.
    const oversizedResponse = await page.request.post(buildE2eUrl("/badges/verify"), {
      multipart: {
        credential: "",
        png: {
          name: "oversized-open-badge.png",
          mimeType: "image/png",
          buffer: Buffer.alloc(12 * 1024 * 1024 + 1),
        },
      },
    });
    expect(oversizedResponse.status()).toBeGreaterThanOrEqual(400);
  });

  test("unknown public badge resources return not found", async ({ request }) => {
    // Request unknown credential, status-list, and retained-key resources.
    const unknownPaths = [
      "/badges/credentials/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      "/badges/status-lists/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      `/badges/issuers/${TEST_GROUP_IDS.community1.alpha}/keys/z6Mkmissingkey`,
    ];

    // Verify none of the opaque resources disclose a substitute document.
    for (const path of unknownPaths) {
      const response = await request.get(buildE2eUrl(path));

      expect(response.status()).toBe(404);
    }

    // Issuer controller documents are derived deterministically for any group
    // id, so unknown issuers still publish a bare profile document.
    const issuerResponse = await request.get(
      buildE2eUrl("/badges/issuers/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
    );
    expect(issuerResponse.status()).toBe(200);
    const issuerDocument = await issuerResponse.json();
    expect(issuerDocument.type).toEqual(["Profile"]);
  });
});
