import { expect, test } from "../../../fixtures.js";

import { navigateToPath } from "../../../utils.js";

test.describe("user dashboard badges", () => {
  test("shows labelled credential actions", async ({ member1Page }) => {
    // Load the badge dashboard with seeded credentials.
    await navigateToPath(member1Page, "/dashboard/user?tab=badges");

    const hostBadge = member1Page.locator("[data-user-badge-id]").filter({
      has: member1Page.getByRole("heading", { name: "Host", exact: true }),
    });
    const badgeArtwork = hostBadge.getByRole("img", { name: "Host badge artwork" });
    const viewCredential = hostBadge.getByRole("link", {
      name: "View Host badge credential",
    });
    const downloadBadge = hostBadge.getByRole("link", {
      name: "Download Host badge as PNG",
    });
    const revokeBadge = hostBadge.getByRole("button", {
      name: "Revoke Host badge",
    });

    // Verify each icon action exposes its purpose.
    await expect(badgeArtwork).toHaveCSS("height", "72px");
    await expect(badgeArtwork).toHaveCSS("width", "72px");
    await expect(viewCredential).toHaveAttribute("title", "View credential");
    await expect(viewCredential.locator(".icon-eye")).toBeVisible();
    await expect(downloadBadge).toHaveAttribute("title", "Download PNG");
    await expect(downloadBadge.locator(".icon-download")).toBeVisible();
    await expect(revokeBadge).toHaveAttribute("title", "Revoke badge");
    await expect(revokeBadge.locator(".icon-trash")).toBeVisible();
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
