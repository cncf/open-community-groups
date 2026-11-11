import { expect, test } from "../../../fixtures.js";
import { setupOwnedExternalCompletedPurchase } from "../../../data-graphs/payments.js";
import {
  TEST_COMMUNITY_NAME,
  TEST_GROUP_IDS,
  TEST_GROUP_SLUG,
  TEST_PAYMENT_EVENT_NAMES,
  TEST_PURCHASE_DOCUMENT_IDS,
  TEST_USER_IDS,
} from "../../../seed.js";
import { buildE2eUrl, expectPaginationNavigation } from "../../../utils.js";
import { getPurchaseRow, openPurchasesDashboard } from "../helpers.js";

test.describe("user dashboard purchases", () => {
  test("empty state explains when no paid-ticket documents exist", async ({ emptyUserPage }) => {
    // Open purchases for the dedicated user without paid tickets.
    const dashboardContent = await openPurchasesDashboard(emptyUserPage);

    // Verify the empty state keeps its document-specific guidance.
    await expect(dashboardContent).toContainText("0 purchases");
    await expect(dashboardContent).toContainText("No paid-ticket documents yet");
    await expect(dashboardContent).toContainText(
      "Invoices appear here after a paid checkout. Free tickets do not create invoices.",
    );
  });

  test("lists refunded purchases with invoice and credit note actions", async ({ adminCommunityPage }) => {
    // Open the seeded refunded purchase with issued financial documents.
    const dashboardContent = await openPurchasesDashboard(adminCommunityPage);
    const purchaseRow = getPurchaseRow(dashboardContent, TEST_PAYMENT_EVENT_NAMES.refunds);

    // Verify the durable purchase summary and seller snapshot.
    await expect(purchaseRow).toBeVisible();
    await expect(purchaseRow).toContainText("VIP pass");
    await expect(purchaseRow).toContainText(/(?:US)?\$50\.00/u);
    await expect(purchaseRow).toContainText("Refunded");
    await expect(purchaseRow).toContainText("E2E Alpha Fiscal Sponsor");

    // Open the document menu and verify both application-owned routes.
    await purchaseRow.getByLabel(`Open document actions for ${TEST_PAYMENT_EVENT_NAMES.refunds}`).click();
    const creditNoteAction = purchaseRow.getByRole("menuitem", {
      name: "Download credit note",
    });
    const invoiceAction = purchaseRow.getByRole("menuitem", {
      name: "View invoice",
    });
    await expect(creditNoteAction).toHaveAttribute(
      "href",
      `/dashboard/user/purchases/${TEST_PURCHASE_DOCUMENT_IDS.purchase}/credit-notes/${TEST_PURCHASE_DOCUMENT_IDS.creditNote}`,
    );
    await expect(invoiceAction).toHaveAttribute(
      "href",
      `/dashboard/user/purchases/${TEST_PURCHASE_DOCUMENT_IDS.purchase}/invoice`,
    );
    // Verify the credit note follows in place, so its download starts without opening a tab,
    // and the invoice opens in a plain new tab.
    await expect(creditNoteAction).toHaveAttribute("rel", "noreferrer");
    await expect(creditNoteAction).not.toHaveAttribute("target", /.*/u);
    await expect(invoiceAction).toHaveAttribute("target", "_blank");
    await expect(invoiceAction).toHaveAttribute("rel", "noopener noreferrer");
  });

  test("purchase documents are private to their attendee", async ({ emptyUserPage }) => {
    // Request another attendee's documents without following provider redirects.
    const invoiceResponse = await emptyUserPage.request.get(
      buildE2eUrl(`/dashboard/user/purchases/${TEST_PURCHASE_DOCUMENT_IDS.purchase}/invoice`),
      { maxRedirects: 0 },
    );
    const creditNoteResponse = await emptyUserPage.request.get(
      buildE2eUrl(
        `/dashboard/user/purchases/${TEST_PURCHASE_DOCUMENT_IDS.purchase}/credit-notes/${TEST_PURCHASE_DOCUMENT_IDS.creditNote}`,
      ),
      { maxRedirects: 0 },
    );

    // Ownership is rejected before any financial-document provider lookup.
    expect(invoiceResponse.status()).toBe(404);
    expect(creditNoteResponse.status()).toBe(404);
  });

  test("keeps unavailable invoices in a disabled processing state", async ({ member1Page }) => {
    // Open a completed purchase whose provider invoice is not available yet.
    const dashboardContent = await openPurchasesDashboard(member1Page);
    const purchaseRow = getPurchaseRow(dashboardContent, TEST_PAYMENT_EVENT_NAMES.refunds);
    await expect(purchaseRow).toContainText("Refund requested");
    await purchaseRow.getByLabel(`Open document actions for ${TEST_PAYMENT_EVENT_NAMES.refunds}`).click();

    // Verify no document link is exposed before the invoice is ready.
    const invoiceAction = purchaseRow.getByRole("menuitem", {
      name: "Invoice processing",
    });
    await expect(invoiceAction).toBeDisabled();
    await expect(invoiceAction).toHaveAttribute("aria-disabled", "true");
    await expect(purchaseRow.getByRole("menuitem", { name: "View invoice" })).toHaveCount(0);
  });

  test("shows paid purchases before their invoice is available", async ({ pending1Page }) => {
    // Open a completed purchase whose invoice is still being reconciled.
    const dashboardContent = await openPurchasesDashboard(pending1Page);
    const purchaseRow = getPurchaseRow(dashboardContent, TEST_PAYMENT_EVENT_NAMES.refunds);

    // Verify the completed purchase remains visible with its document state.
    await expect(purchaseRow).toContainText("Paid");
    await purchaseRow.getByLabel(`Open document actions for ${TEST_PAYMENT_EVENT_NAMES.refunds}`).click();
    await expect(purchaseRow.getByRole("menuitem", { name: "Invoice processing" })).toBeDisabled();
  });

  test("keeps the document menu of a single purchase unclipped at md", async ({ pending1Page }) => {
    // Open the only purchase of the dedicated user at the md review width.
    await pending1Page.setViewportSize({ width: 771, height: 900 });
    const dashboardContent = await openPurchasesDashboard(pending1Page);
    await expect(dashboardContent.locator("tbody tr")).toHaveCount(1);
    const purchaseRow = getPurchaseRow(dashboardContent, TEST_PAYMENT_EVENT_NAMES.refunds);

    // Open the document menu below the last table row.
    await purchaseRow.getByLabel(`Open document actions for ${TEST_PAYMENT_EVENT_NAMES.refunds}`).click();
    const lastMenuItem = purchaseRow.getByRole("menuitem").last();
    await expect(lastMenuItem).toBeVisible();

    // Verify the last item is inside the viewport and receives hits at its centre (not clipped).
    const menuItemHit = await lastMenuItem.evaluate((item) => {
      const box = item.getBoundingClientRect();
      const target = document.elementFromPoint(box.left + box.width / 2, box.top + box.height / 2);

      return {
        hitsItem: target !== null && item.contains(target),
        insideViewport:
          box.top >= 0 && box.left >= 0 && box.bottom <= window.innerHeight && box.right <= window.innerWidth,
      };
    });
    expect(menuItemHit).toEqual({ hitsItem: true, insideViewport: true });

    // Verify the dashboard content does not scroll horizontally.
    const contentWidths = await dashboardContent.evaluate((content) => ({
      clientWidth: content.clientWidth,
      scrollWidth: content.scrollWidth,
    }));
    expect(contentWidths.scrollWidth).toBeLessThanOrEqual(contentWidths.clientWidth);
  });

  test("labels externally managed purchases as External", async ({ member2Page, owned }) => {
    // Create an owned paid event with a completed external purchase for the attendee.
    const event = owned.event({
      groupId: TEST_GROUP_IDS.community1.alpha,
      paymentCurrencyCode: "USD",
      tiers: [{ amountMinor: 5000, key: "general", seats: 10, title: "General admission" }],
    });
    setupOwnedExternalCompletedPurchase({ eventId: event.eventId, userId: TEST_USER_IDS.member2 });

    // Verify the visible status badges use the short External label.
    const dashboardContent = await openPurchasesDashboard(member2Page);
    const purchaseRow = getPurchaseRow(dashboardContent, event.name);
    await expect(purchaseRow.getByText("External", { exact: true }).filter({ visible: true })).toHaveCount(1);
    await expect(purchaseRow).not.toContainText("Externally managed");

    // Verify the document menu explains the purchase is managed outside OCG.
    await purchaseRow.getByLabel(`Open document actions for ${event.name}`).click();
    await expect(purchaseRow.getByText("Managed outside OCG")).toBeVisible();
  });

  test("shows processing and failed credit note states", async ({
    eventsManagerGroupPage,
    organizerGroupWithoutPaymentsPage,
  }) => {
    // Verify an in-flight refund exposes both processing document labels.
    const processingDashboard = await openPurchasesDashboard(organizerGroupWithoutPaymentsPage);
    const processingRow = getPurchaseRow(processingDashboard, TEST_PAYMENT_EVENT_NAMES.refunds);
    await expect(processingRow).toContainText("Refund processing");
    await processingRow.getByLabel(`Open document actions for ${TEST_PAYMENT_EVENT_NAMES.refunds}`).click();
    await expect(processingRow.getByRole("menuitem", { name: "Credit note processing" })).toBeDisabled();
    await expect(processingRow.getByRole("menuitem", { name: "Invoice processing" })).toBeDisabled();

    // Verify an exhausted credit-note job is presented for review, not download.
    const failedDashboard = await openPurchasesDashboard(eventsManagerGroupPage);
    const failedRow = getPurchaseRow(failedDashboard, TEST_PAYMENT_EVENT_NAMES.refunds);
    await failedRow.getByLabel(`Open document actions for ${TEST_PAYMENT_EVENT_NAMES.refunds}`).click();
    await expect(failedRow.getByRole("menuitem", { name: "Credit note needs review" })).toBeDisabled();
    await expect(failedRow.getByRole("menuitem", { name: "Download credit note" })).toHaveCount(0);
  });

  test("keeps past and canceled purchases in durable history", async ({ adminCommunityPage }) => {
    // Open the complete durable history for the seeded administrator.
    const dashboardContent = await openPurchasesDashboard(adminCommunityPage);
    const pastPurchaseRow = getPurchaseRow(dashboardContent, "Past Event For Filtering");
    const canceledPurchaseRow = getPurchaseRow(dashboardContent, "Canceled Public Event");

    // Verify past events retain their public link and issued invoice action.
    await expect(pastPurchaseRow).toBeVisible();
    await expect(pastPurchaseRow.getByRole("link", { name: "Past Event For Filtering" })).toHaveAttribute(
      "href",
      `/${TEST_COMMUNITY_NAME}/group/${TEST_GROUP_SLUG}/event/alpha-past-roundup`,
    );
    await pastPurchaseRow.getByLabel("Open document actions for Past Event For Filtering").click();
    await expect(pastPurchaseRow.getByRole("menuitem", { name: "View invoice" })).toBeVisible();

    // Verify canceled events remain visible with the recovery state made explicit.
    await expect(canceledPurchaseRow).toContainText("Event canceled");
    await expect(canceledPurchaseRow).toContainText("Refund needs review");
  });

  test("user can paginate durable purchase history", async ({ adminCommunityPage }) => {
    // Paginate the three seeded document-history rows one at a time.
    await expectPaginationNavigation(
      adminCommunityPage,
      "/dashboard/user?tab=purchases&limit=1&offset=0",
      "#dashboard-content tbody tr",
    );
  });
});
