import { expect, test } from "../../fixtures.js";

import { buildE2eUrl, getPageOverflow, navigateToPath } from "../../utils.js";

const ACTIVE_CREDENTIAL_ID = "dadadada-dada-dada-dada-dadadadada02";
const ACTIVE_CREDENTIAL_IMAGE_FILE_NAME =
  "7744970faed216a0b2d3be30ffef5aeb1bd6b65c5407ccc4f3dd824d132f1656.png";
const ACTIVE_CREDENTIAL_SHARE_DESCRIPTION = "Platform Ops Meetup (Platform Engineering Community)";
const PHONE_VIEWPORTS = [
  { height: 568, width: 320 },
  { height: 874, width: 402 },
];
const REVOKED_CREDENTIAL_ID = "dadadada-dada-dada-dada-dadadadada04";

test.describe("public badge credential page", () => {
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
    await expect(page.locator('dt:text-is("Awarded") + dd')).toHaveText(/^\s*\d{4}-\d{2}-\d{2}\s*$/);
    await expect(page.getByText("Criteria", { exact: true })).toBeVisible();
    await expect(
      page.getByText("Serve as a host for a Platform Ops Meetup event.", {
        exact: true,
      }),
    ).toBeVisible();
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

  test("credential page publishes share metadata with a cross-origin badge image", async ({
    page,
    request,
  }) => {
    const credentialUrl = buildE2eUrl(`/badges/credentials/${ACTIVE_CREDENTIAL_ID}`);
    const imageUrl = buildE2eUrl(`/images/badges/${ACTIVE_CREDENTIAL_IMAGE_FILE_NAME}`);

    // Load an active public badge credential.
    await navigateToPath(page, `/badges/credentials/${ACTIVE_CREDENTIAL_ID}`);

    // Verify titles and descriptions name the badge and its issuer.
    await expect(page.locator('meta[property="og:title"]')).toHaveAttribute("content", "Host");
    await expect(page.locator('meta[name="twitter:title"]')).toHaveAttribute("content", "Host");
    await expect(page.locator('meta[name="description"]')).toHaveAttribute(
      "content",
      ACTIVE_CREDENTIAL_SHARE_DESCRIPTION,
    );
    await expect(page.locator('meta[property="og:description"]')).toHaveAttribute(
      "content",
      ACTIVE_CREDENTIAL_SHARE_DESCRIPTION,
    );
    await expect(page.locator('meta[name="twitter:description"]')).toHaveAttribute(
      "content",
      ACTIVE_CREDENTIAL_SHARE_DESCRIPTION,
    );

    // Verify share URLs are absolute so previews resolve off-site.
    await expect(page.locator('meta[property="og:url"]')).toHaveAttribute("content", credentialUrl);
    await expect(page.locator('meta[property="og:image"]')).toHaveAttribute("content", imageUrl);
    await expect(page.locator('meta[property="og:image:alt"]')).toHaveAttribute("content", "Host");
    await expect(page.locator('meta[name="twitter:card"]')).toHaveAttribute("content", "summary_large_image");
    await expect(page.locator('meta[name="twitter:image"]')).toHaveAttribute("content", imageUrl);

    // Fetch the artwork as a link-preview crawler would, without a Referer.
    const imageResponse = await request.get(imageUrl);
    const imageHeaders = imageResponse.headers();
    expect(imageResponse.status()).toBe(200);
    expect(imageHeaders["content-type"]).toBe("image/png");
    expect(imageHeaders["cross-origin-resource-policy"]).toBe("cross-origin");
  });

  for (const { height, width } of PHONE_VIEWPORTS) {
    test(`credential card stacks at ${width}px @mobile`, async ({ page }) => {
      // Load the credential at this phone size.
      await page.setViewportSize({ height, width });
      await navigateToPath(page, `/badges/credentials/${ACTIVE_CREDENTIAL_ID}`);
      await expect(page.getByRole("heading", { name: "Host" })).toBeVisible();

      // Verify the header height and the card's 12px gutter.
      expect((await page.getByRole("navigation", { name: "Badge navigation" }).boundingBox()).height).toBe(
        64,
      );
      const card = await page.locator("article").boundingBox();
      expect(card.x).toBe(12);
      expect(card.width).toBe(width - 24);

      // Verify the art is centred above a centred title.
      const art = await page.getByAltText("Host badge artwork").boundingBox();
      expect(art.width).toBe(160);
      expect(art.x + art.width / 2).toBeCloseTo(width / 2, 0);
      await expect(page.getByRole("heading", { name: "Host" })).toHaveCSS("text-align", "center");

      // Verify the page does not scroll sideways.
      expect(await getPageOverflow(page)).toBeLessThanOrEqual(0);
    });
  }

  test("revoked pill stays readable over broken artwork @mobile", async ({ page }) => {
    // Break the artwork, which is what a failed image host looks like.
    await page.route("**/images/badges/**", (route) => route.abort());
    await navigateToPath(page, `/badges/credentials/${REVOKED_CREDENTIAL_ID}`);

    // Verify the pill is painted on top at its own centre.
    const pill = page.getByText("Permanently revoked", { exact: true });
    await expect(pill).toBeVisible();
    const isOnTop = await pill.evaluate((element) => {
      const { height, width, x, y } = element.getBoundingClientRect();
      return document.elementFromPoint(x + width / 2, y + height / 2) === element;
    });
    expect(isOnTop).toBe(true);
  });
});
