import { expect, test } from "../../fixtures.js";

import { TEST_COMMUNITY_NAME, TEST_EVENT_SLUG, TEST_GROUP_IDS, TEST_GROUP_SLUGS } from "../../seed.js";
import { buildE2eUrl, navigateToEvent } from "../../utils.js";

const ACTIVE_CREDENTIAL_ID = "dadadada-dada-dada-dada-dadadadada02";
const BADGE_STATUS_LIST_ID = "cacacaca-caca-caca-caca-cacacacaca01";
const MEMBER_HOST_CREDENTIAL_ID = "dadadada-dada-dada-dada-dadadadada06";
const REVOKED_CREDENTIAL_ID = "dadadada-dada-dada-dada-dadadadada04";

test.describe("public badge resources", () => {
  test("publishes credential, issuer, and status-list JSON contracts", async ({ request }) => {
    // Request the signed credential representation.
    const credentialResponse = await request.get(buildE2eUrl(`/badges/credentials/${ACTIVE_CREDENTIAL_ID}`), {
      headers: { Accept: "application/vc+ld+json" },
    });
    const credential = await credentialResponse.json();

    // Verify the credential document preserves the public VC contract.
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

    // Verify the issuer profile references retained assertion methods.
    expect(issuerResponse.ok()).toBeTruthy();
    expect(issuer.id).toBe(buildE2eUrl(`/badges/issuers/${TEST_GROUP_IDS.community1.alpha}`));
    expect(issuer.assertionMethod).not.toHaveLength(0);
    expect(issuer.verificationMethod).not.toHaveLength(0);

    // Verify the referenced status list is a signed credential.
    const statusResponse = await request.get(buildE2eUrl(`/badges/status-lists/${BADGE_STATUS_LIST_ID}`));
    const statusList = await statusResponse.json();

    // Verify the status list document preserves its signed VC contract.
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

  test("profile modal lists exactly the public badge names", async ({ page }) => {
    // Open the public event page that renders the seeded member profile trigger.
    await navigateToEvent(page, TEST_COMMUNITY_NAME, TEST_GROUP_SLUGS.community1.alpha, TEST_EVENT_SLUG);
    // The same speaker can appear in more than one event section; either chip opens the same profile.
    await page.getByRole("button", { name: "View E2E Member Two's profile" }).first().click();

    // Verify the modal renders only listed, active badge credentials.
    const profileDialog = page.getByRole("dialog", {
      name: /User(?: Information)?/u,
    });
    await expect(profileDialog).toBeVisible();
    await expect(profileDialog).toContainText("E2E Member Two");
    await expect
      .poll(async () => {
        return profileDialog
          .getByRole("link", { name: /badge credential/u })
          .evaluateAll((links) =>
            links.map((link) =>
              link.getAttribute("aria-label").replace(/^View (.+) badge credential$/u, "$1"),
            ),
          );
      })
      .toEqual(["Mentor", "Volunteer"]);
    await expect(profileDialog.getByRole("link", { name: "View Speaker badge credential" })).toHaveCount(0);

    // Close the modal so later tests keep a clean page state.
    await profileDialog.getByRole("button", { name: "Close modal" }).click();
    await expect(profileDialog).toBeHidden();
  });
});
