import { expect, test } from "../../../fixtures.js";

import {
  cleanupOwnedPaymentPurchase,
  setupExhaustedFinancialWorkGraph,
  setupExternalRefundRequestGraph,
  setupRecoverableRefundGraph,
} from "../../../data-graphs/payments.js";
import { TEST_USER_IDS } from "../../../seed.js";
import { enableDesktopVersion, expectAriaSnapshot, expectPageLayout } from "../../../snapshots.js";
import { openActionsMenu, openGroupDashboardView, setupAriaEvent, setupAriaGroup } from "../aria-helpers.js";

test.describe("group dashboard refunds ARIA snapshots", () => {
  test("matches the desktop views", async ({ organizerGroupPage, owned }) => {
    await expectRefundsViews({ owned, page: organizerGroupPage });
  });

  test("matches the views in the mobile desktop version @mobile", async ({ organizerGroupPage, owned }) => {
    await enableDesktopVersion(organizerGroupPage);
    await expectRefundsViews({ owned, page: organizerGroupPage });
  });
});

/** Checks the layout of the refunds tab views and captures them. */
const expectRefundsViews = async ({ owned, page }) => {
  const { groupId } = await setupAriaGroup({ owned, page });
  const main = page.locator("#dashboard-main-content");

  await test.step("empty state", async () => {
    // Load the refunds of a temporary group without purchases and check the layout.
    await openGroupDashboardView(page, "tab=refunds");

    // Capture the payments warning, the title, the filters and the empty state.
    await expectAriaSnapshot(page, main, "refunds-empty");
  });

  // Give an owned paid event a refund request, a recoverable refund and exhausted financial work.
  const { eventId } = setupAriaEvent({
    groupId,
    owned,
    paymentCurrencyCode: "USD",
    tiers: [{ amountMinor: 5000, key: "general", seats: 10, title: "General admission" }],
  });
  for (const [setup, userId] of [
    [setupExternalRefundRequestGraph, TEST_USER_IDS.member3],
    [setupRecoverableRefundGraph, TEST_USER_IDS.pending1],
    [setupExhaustedFinancialWorkGraph, TEST_USER_IDS.pending2],
  ]) {
    owned.track(setup({ eventId, userId }), cleanupOwnedPaymentPurchase);
  }
  const attention = page.getByRole("table", { name: "Financial work needing attention" });
  const refunds = page.getByRole("table", { name: "Refunds list" });
  // Both refunds start in the same second, so their order varies and each row is captured alone.
  const requestRow = refunds.getByRole("row").filter({ hasText: "Needs review" });
  const recoveryRow = refunds.getByRole("row").filter({ hasText: "Recovery required" });

  await test.step("active refunds", async () => {
    // Load the active refunds and check the layout.
    await openGroupDashboardView(page, "tab=refunds", { regions: [attention, refunds] });

    // Capture the financial work needing attention and each refund row.
    await expectAriaSnapshot(page, attention, "refunds-attention-work");
    await expectAriaSnapshot(page, requestRow, "refunds-request-row");
    await expectAriaSnapshot(page, recoveryRow, "refunds-recovery-row");
  });

  await test.step("refund details tooltip", async () => {
    // Focus the amount of the refund request to show its details and check the layout.
    const tooltip = requestRow.getByRole("tooltip");
    await requestRow.getByRole("button", { name: /^\$\d/ }).focus();
    await expect(tooltip).toBeVisible();
    await expectPageLayout(page, { regions: [tooltip] });

    // Capture the ticket, request kind and start date; the date is the test day.
    await expectAriaSnapshot(page, tooltip, "refunds-details-tooltip");
  });

  await test.step("needs attention view", async () => {
    // Load the refunds needing attention and check the layout.
    const filters = page.locator("#refund-filters");
    await openGroupDashboardView(page, "tab=refunds&view=attention", { regions: [filters, refunds] });

    // Capture the filters with the attention view selected and both refunds, which need review or recovery.
    await expectAriaSnapshot(page, filters, "refunds-attention-filters");
    await expectAriaSnapshot(page, requestRow, "refunds-request-row");
    await expectAriaSnapshot(page, recoveryRow, "refunds-recovery-row");
  });

  await test.step("refund actions menus", async () => {
    // Open the actions of the refund request and of the recoverable refund, and capture them.
    const requestMenu = await openActionsMenu(page, "Open refund actions for E2E Member Three");
    await expectAriaSnapshot(page, requestMenu, "refunds-request-actions");
    await page.getByLabel("Open refund actions for E2E Member Three").click();
    await expect(requestMenu).toBeHidden();
    const recoveryMenu = await openActionsMenu(page, "Open refund actions for E2E Pending One");
    await expectAriaSnapshot(page, recoveryMenu, "refunds-recovery-actions");
  });

  await test.step("refund recovery dialog", async () => {
    // Open the recovery form of the recoverable refund and check the layout.
    const dialog = page.getByRole("dialog", { name: "Complete refund recovery" });
    await page.getByRole("button", { name: "Complete recovery" }).click();
    await expect(dialog).toBeVisible();
    await expectPageLayout(page, { regions: [dialog] });

    // Capture the refund summary and the evidence fields.
    await expectAriaSnapshot(page, dialog, "refunds-recovery-dialog");
  });

  await test.step("financial recovery dialog", async () => {
    // Open the outside completion form of the exhausted financial work and check the layout.
    const dialog = page.locator("#financial-recovery-modal");
    await openGroupDashboardView(page, "tab=refunds", { regions: [attention] });
    const menu = await openActionsMenu(page, "Open financial recovery actions for Credit note");
    await expectAriaSnapshot(page, menu, "refunds-financial-work-actions");
    await menu.getByRole("button", { name: "Complete outside OCG" }).click();
    await expect(dialog).toBeVisible();
    await expectPageLayout(page, { regions: [dialog] });

    // Capture the work summary and the evidence fields.
    await expectAriaSnapshot(page, dialog, "refunds-financial-recovery-dialog");
  });
};
