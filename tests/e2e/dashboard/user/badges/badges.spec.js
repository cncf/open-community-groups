import { expect, test } from "../../../fixtures.js";

import { navigateToPath } from "../../../utils.js";

test.describe("user dashboard badges", () => {
  test("shows labelled credential actions", async ({ member1Page }) => {
    // Load the badge dashboard with seeded credentials.
    await navigateToPath(member1Page, "/dashboard/user?tab=badges");

    const hostBadge = member1Page.locator("[data-user-badge-id]").filter({
      has: member1Page.getByRole("heading", { name: "Host", exact: true }),
    });
    const badgeActions = hostBadge.getByRole("group", { name: "Host badge actions" });
    const badgeArtwork = hostBadge.getByRole("img", { name: "Host badge artwork" });
    const communityName = hostBadge.getByText("Platform Engineering Community", { exact: true });
    const viewCredential = hostBadge.getByRole("link", {
      name: "View Host badge credential",
    });
    const downloadBadge = hostBadge.getByRole("link", {
      name: "Download Host badge as PNG",
    });
    const revokeBadge = hostBadge.getByRole("button", {
      name: "Revoke Host badge",
    });

    // Verify issuer information and each icon action.
    await expect(badgeActions).toBeVisible();
    await expect(badgeArtwork).toHaveCSS("height", "80px");
    await expect(badgeArtwork).toHaveCSS("width", "80px");
    await expect(communityName).toBeVisible();
    await expect(viewCredential).toHaveAttribute("title", "View credential");
    await expect(viewCredential.locator(".icon-eye")).toBeVisible();
    await expect(downloadBadge).toHaveAttribute("title", "Download PNG");
    await expect(downloadBadge.locator(".icon-download")).toBeVisible();
    await expect(revokeBadge).toHaveAttribute("title", "Revoke badge");
    await expect(revokeBadge.locator(".icon-trash")).toBeVisible();

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

    const layout = await hostBadge.evaluate((badge) => {
      const actions = badge.querySelector('[role="group"]');
      const title = badge.querySelector("h2");
      const description = title?.parentElement?.nextElementSibling;

      if (!actions || !description || !title) {
        throw new Error("Badge card layout elements are missing");
      }

      const actionsBounds = actions.getBoundingClientRect();
      const descriptionBounds = description.getBoundingClientRect();
      const titleBounds = title.getBoundingClientRect();

      return {
        actionsLeft: actionsBounds.left,
        actionsVerticalCenter: actionsBounds.top + actionsBounds.height / 2,
        descriptionRight: descriptionBounds.right,
        titleVerticalCenter: titleBounds.top + titleBounds.height / 2,
      };
    });

    expect(Math.abs(layout.actionsVerticalCenter - layout.titleVerticalCenter)).toBeLessThanOrEqual(1);
    expect(layout.descriptionRight).toBeGreaterThan(layout.actionsLeft);
  });

  test("shows the community as secondary issuer information", async ({ member1Page }) => {
    // Open a seeded credential from the badge dashboard.
    await navigateToPath(member1Page, "/dashboard/user?tab=badges");
    const credentialPath = await member1Page
      .getByRole("link", { name: "View Host badge credential" })
      .getAttribute("href");
    expect(credentialPath).not.toBeNull();
    await navigateToPath(member1Page, credentialPath);

    const communityName = member1Page.getByText("Platform Engineering Community", { exact: true });

    // Verify the community is styled as a distinct secondary line.
    await expect(communityName).toBeVisible();
    await expect(communityName).toHaveCSS("display", "block");
    await expect(communityName).toHaveCSS("font-weight", "600");
    await expect(communityName).toHaveCSS("text-transform", "uppercase");
    await expect(communityName).toHaveClass(/text-stone-500/u);
  });
});
