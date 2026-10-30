import { expect, test } from "../../../fixtures.js";
import { queryE2eDatabase } from "../../../database.js";
import { cleanupCredential, setupRevocableCredential } from "../../../data-graphs/badges.js";
import { TEST_GROUP_IDS, TEST_USER_IDS } from "../../../seed.js";
import { buildE2eUrl, navigateToPath, waitForActionResponse } from "../../../utils.js";

const BADGE_LAYOUT_WIDTHS = [768, 1024, 1280];
const HOST_CREDENTIAL_ID = "dadadada-dada-dada-dada-dadadadada06";

test.describe("user dashboard badges", () => {
  test("empty state explains where awarded badges will appear", async ({ emptyUserPage }) => {
    // Load badges for the dedicated user without awarded credentials.
    await navigateToPath(emptyUserPage, "/dashboard/user?tab=badges");
    const emptyState = emptyUserPage.locator("[data-user-badges-empty]");

    // Verify the empty card names the state and its source of future content.
    await expect(emptyState).toContainText("No active badges yet");
    await expect(emptyState).toContainText("Badges awarded by your groups will appear here.");
  });

  test("shows labelled credential actions", async ({ member1Page }) => {
    // Load the badge dashboard with seeded credentials.
    await navigateToPath(member1Page, "/dashboard/user?tab=badges");

    const hostBadge = member1Page.locator("[data-user-badge-id]").filter({
      has: member1Page.getByRole("heading", { name: "Host", exact: true }),
    });
    const badgeList = member1Page.locator("[data-badge-order-list]");
    const badgeActions = hostBadge.getByRole("group", { name: "Host badge actions" });
    const badgeArtwork = hostBadge.locator("[data-badge-artwork-image]");
    const issuerInformation = hostBadge.getByText(
      "Issued by Platform Ops Meetup (Platform Engineering Community)",
      { exact: true },
    );
    const shareCredential = hostBadge.getByRole("button", {
      name: "Share Host badge credential",
    });
    const downloadBadge = hostBadge.getByRole("link", {
      name: "Download Host badge as PNG",
    });
    const revokeBadge = hostBadge.getByRole("button", {
      name: "Revoke Host badge",
    });

    // Verify issuer information and each icon action.
    await expect(badgeList).toHaveAttribute("data-badge-controls-ready", "true");
    await expect(badgeActions).toBeVisible();
    await expect(badgeArtwork).toBeVisible();
    await expect(badgeArtwork).toHaveCSS("height", "80px");
    await expect(badgeArtwork).toHaveCSS("width", "80px");
    await expect(issuerInformation).toBeVisible();
    await expect(shareCredential).toHaveAttribute("title", "Share Host badge credential");
    await expect(shareCredential.locator(".icon-share")).toBeVisible();
    await expect(downloadBadge).toHaveAttribute("title", "Download PNG");
    await expect(downloadBadge.locator(".icon-download")).toBeVisible();
    await expect(revokeBadge).toHaveAttribute("title", "Revoke badge");
    await expect(revokeBadge.locator(".icon-trash")).toBeVisible();

    // Open and close the credential share dialog.
    await shareCredential.click();
    const shareDialog = member1Page.getByRole("dialog", { name: "Share" });
    await expect(shareDialog).toBeVisible();
    await expect(shareDialog.getByRole("button", { name: "Copy link" })).toBeVisible();
    await shareDialog.getByRole("button", { name: "Close modal" }).click();

    // Open the protected download confirmation and verify its guidance.
    await downloadBadge.click();
    await expect(member1Page.getByRole("heading", { name: "Download Host badge?" })).toBeVisible();
    await expect(
      member1Page.getByText("signed Open Badges 3.0 credential data", { exact: false }),
    ).toBeVisible();
    await expect(member1Page.getByRole("button", { name: "Download PNG" })).toBeVisible();
    await expect(member1Page.getByRole("link", { name: "Read the badge export guide" })).toHaveAttribute(
      "href",
      "/docs#/guides/badges?id=share-and-export-credentials",
    );
    await member1Page.getByRole("button", { name: "Cancel" }).click();

    // Measure the card layout after every action returns to its resting state.
    const layout = await measureBadgeCard(hostBadge);

    // Verify actions align with the title without constraining description width.
    expect(Math.abs(layout.actionsTop - layout.titleTop)).toBeLessThanOrEqual(1);
    expect(layout.descriptionRight).toBeGreaterThan(layout.actionsLeft);
  });

  test("keeps the credential card layout at each dashboard band", async ({ member1Page }) => {
    // Load the badge dashboard at the narrowest supported width.
    await member1Page.setViewportSize({ width: 768, height: 900 });
    await navigateToPath(member1Page, "/dashboard/user?tab=badges");
    const hostBadge = member1Page.locator("[data-user-badge-id]").filter({
      has: member1Page.getByRole("heading", { name: "Host", exact: true }),
    });
    const listingToggle = hostBadge.getByRole("checkbox", { name: "Show on profile" });
    await expect(member1Page.locator("[data-badge-order-list]")).toHaveAttribute(
      "data-badge-controls-ready",
      "true",
    );

    for (const width of BADGE_LAYOUT_WIDTHS) {
      // Resize and measure the resting card layout.
      await member1Page.setViewportSize({ width, height: 900 });
      const layout = await measureBadgeCard(hostBadge);

      // Verify actions align with the title without constraining description width.
      expect(Math.abs(layout.actionsTop - layout.titleTop), `${width}px title row`).toBeLessThanOrEqual(1);
      expect(layout.descriptionRight, `${width}px description width`).toBeGreaterThan(layout.actionsLeft);

      // Verify the description clamp and the listing toggle placement per band.
      expect(layout.descriptionLineClamp, `${width}px description clamp`).toBe(width < 1280 ? "2" : "none");
      if (width < 1024) {
        expect(layout.toggleTop, `${width}px toggle below artwork`).toBeGreaterThan(layout.artworkBottom);
      }

      // Verify the listing toggle still receives pointer input.
      expect(layout.toggleHit, `${width}px toggle hit test`).toBe(true);
      await expect(listingToggle).toBeEnabled();
    }
  });

  test("share modal links to the public credential page", async ({ member1Page }) => {
    // Read the share link from the seeded Host credential card.
    await navigateToPath(member1Page, "/dashboard/user?tab=badges");
    const hostBadge = member1Page.locator("[data-user-badge-id]").filter({
      has: member1Page.getByRole("heading", { name: "Host", exact: true }),
    });
    const credentialPath = `/badges/credentials/${HOST_CREDENTIAL_ID}`;
    await expect(hostBadge.locator("share-modal")).toHaveAttribute("url", credentialPath);

    // Verify the shared link opens the public credential page.
    await navigateToPath(member1Page, credentialPath);
    await expect(member1Page).toHaveTitle("Host badge");
  });

  test("persists profile visibility and restores the seeded setting", async ({ member1Page }) => {
    // Locate the seeded Host credential and hide it from the public profile.
    await navigateToPath(member1Page, "/dashboard/user?tab=badges");
    const hostBadge = member1Page.locator("[data-user-badge-id]").filter({
      has: member1Page.getByRole("heading", { name: "Host", exact: true }),
    });
    const listingToggle = hostBadge.getByRole("checkbox", {
      name: "Show on profile",
    });
    const badgeList = member1Page.locator("[data-badge-order-list]");

    // Verify the seeded credential is ready and visible on the profile.
    await expect(badgeList).toHaveAttribute("data-badge-controls-ready", "true");
    await expect(listingToggle).toBeChecked();
    try {
      // Hide the Host credential from the public profile.
      await waitForActionResponse(member1Page, () => setListingValue(listingToggle, false), {
        method: "PUT",
        urlEndsWith: `/badges/${HOST_CREDENTIAL_ID}/listing`,
      });
      await expect(listingToggle).not.toBeChecked();

      // Verify both a reload and the public endpoint reflect the saved state.
      await member1Page.reload();
      await expect(
        member1Page
          .locator(`[data-user-badge-id="${HOST_CREDENTIAL_ID}"]`)
          .getByRole("checkbox", { name: "Show on profile" }),
      ).not.toBeChecked();
      const profileResponse = await member1Page.request.get(buildE2eUrl("/users/e2e-member-1/badges"));
      const profileBadges = await profileResponse.json();
      expect(profileResponse.ok()).toBeTruthy();
      expect(profileBadges).not.toEqual(
        expect.arrayContaining([expect.objectContaining({ user_badge_id: HOST_CREDENTIAL_ID })]),
      );
    } finally {
      // Restore the Host credential to the public profile when needed.
      if (!member1Page.isClosed()) {
        const currentToggle = member1Page
          .locator(`[data-user-badge-id="${HOST_CREDENTIAL_ID}"]`)
          .getByRole("checkbox", { name: "Show on profile" });

        if (!(await currentToggle.isChecked())) {
          await waitForActionResponse(member1Page, () => setListingValue(currentToggle, true), {
            method: "PUT",
            urlEndsWith: `/badges/${HOST_CREDENTIAL_ID}/listing`,
          });
        }
      }
    }
  });

  test("persists keyboard ordering and restores the seeded order", async ({ member1Page }) => {
    // Move Host above Speaker using the documented keyboard interaction.
    await navigateToPath(member1Page, "/dashboard/user?tab=badges");
    const badgeList = member1Page.locator("[data-badge-order-list]");
    const hostHandle = member1Page.getByRole("button", {
      name: "Reorder Host",
    });

    // Verify the seeded badge order before moving it.
    await expect(badgeList.locator("[data-user-badge-id]").first()).toContainText("Speaker");
    try {
      // Move the Host badge above Speaker.
      await waitForActionResponse(member1Page, () => hostHandle.press("ArrowUp"), {
        method: "PUT",
        urlEndsWith: "/dashboard/user/badges/order",
      });
      await expect(badgeList.locator("[data-user-badge-id]").first()).toContainText("Host");

      // Reload to prove the order was persisted by the server.
      await member1Page.reload();
      await expect(member1Page.locator("[data-badge-order-list] [data-user-badge-id]").first()).toContainText(
        "Host",
      );
    } finally {
      // Restore the Host badge to its seeded order when needed.
      if (!member1Page.isClosed()) {
        const restoredHostHandle = member1Page.getByRole("button", {
          name: "Reorder Host",
        });
        const firstBadge = member1Page.locator("[data-badge-order-list] [data-user-badge-id]").first();

        if ((await firstBadge.getAttribute("data-user-badge-id")) === HOST_CREDENTIAL_ID) {
          await waitForActionResponse(member1Page, () => restoredHostHandle.press("ArrowDown"), {
            method: "PUT",
            urlEndsWith: "/dashboard/user/badges/order",
          });
        }
      }
    }
  });

  test("user can permanently revoke an owned credential", async ({ member2Page }) => {
    const credential = setupRevocableCredential({
      groupId: TEST_GROUP_IDS.community1.alpha,
      userId: TEST_USER_IDS.member2,
    });

    try {
      // Open the disposable credential and confirm the destructive action.
      await navigateToPath(member2Page, "/dashboard/user?tab=badges");
      const ownedBadge = member2Page.locator(`[data-user-badge-id="${credential.userBadgeId}"]`);

      // Confirm the revocation for the disposable credential.
      await expect(ownedBadge).toContainText(credential.badgeName);
      await ownedBadge.getByRole("button", { name: `Revoke ${credential.badgeName} badge` }).click();
      await expect(
        member2Page.getByRole("heading", {
          name: `Permanently revoke ${credential.badgeName}?`,
        }),
      ).toBeVisible();
      await waitForActionResponse(
        member2Page,
        () => member2Page.getByRole("button", { name: "Permanently revoke" }).click(),
        {
          method: "DELETE",
          urlEndsWith: `/dashboard/user/badges/${credential.userBadgeId}`,
        },
      );

      // Verify it leaves the active dashboard but retains its public history and reason.
      await expect(ownedBadge).toHaveCount(0);
      expect(
        queryE2eDatabase(`
          select revocation_reason
          from user_badge
          where user_badge_id = '${credential.userBadgeId}'::uuid
        `),
      ).toBe("recipient revoked badge");
      await navigateToPath(member2Page, `/badges/credentials/${credential.userBadgeId}`);
      await expect(member2Page.getByText("Permanently revoked", { exact: true })).toBeVisible();
    } finally {
      // Remove the disposable credential record.
      cleanupCredential(credential);
    }
  });
});

/**
 * Measures the badge card title row, description, artwork and listing toggle.
 * @param {import("@playwright/test").Locator} badge - Badge row locator.
 * @returns {Promise<object>} Card bounds, description clamp and toggle hit test.
 */
const measureBadgeCard = (badge) =>
  badge.evaluate((card) => {
    const actions = card.querySelector('[role="group"]');
    const artwork = card.querySelector("[data-badge-artwork]");
    const title = card.querySelector("h2");
    const description = title?.parentElement?.nextElementSibling;
    const toggle = card.querySelector("[data-badge-listing]")?.closest("label");

    if (!actions || !artwork || !description || !title || !toggle) {
      throw new Error("Badge card layout elements are missing");
    }

    const actionsBounds = actions.getBoundingClientRect();
    const descriptionBounds = description.getBoundingClientRect();
    const titleBounds = title.getBoundingClientRect();
    const toggleBounds = toggle.getBoundingClientRect();
    const hitTarget = document.elementFromPoint(
      toggleBounds.left + toggleBounds.width / 2,
      toggleBounds.top + toggleBounds.height / 2,
    );

    return {
      actionsLeft: actionsBounds.left,
      actionsTop: actionsBounds.top,
      artworkBottom: artwork.getBoundingClientRect().bottom,
      descriptionLineClamp: getComputedStyle(description).webkitLineClamp,
      descriptionRight: descriptionBounds.right,
      titleTop: titleBounds.top,
      toggleHit: Boolean(hitTarget && toggle.contains(hitTarget)),
      toggleTop: toggleBounds.top,
    };
  });

/** Sets the listing toggle value and dispatches its change event. */
const setListingValue = (toggle, isListed) =>
  toggle.evaluate((control, checked) => {
    control.checked = checked;
    control.dispatchEvent(new Event("change", { bubbles: true }));
  }, isListed);
