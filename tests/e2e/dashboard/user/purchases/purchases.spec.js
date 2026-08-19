import { expect, test } from "../../../fixtures.js";

import {
  E2E_PAYMENTS_ENABLED,
  TEST_COMMUNITY_NAME,
  TEST_GROUP_SLUG,
  TEST_PAYMENT_EVENT_NAMES,
  TEST_PURCHASE_DOCUMENT_IDS,
  buildE2eUrl,
  expectPaginationNavigation,
  expectTableColumnsAtViewport,
  expectTableHeaders,
  navigateToPath,
} from "../../../utils.js";

const openPurchasesDashboard = async (page) => {
  await navigateToPath(page, "/dashboard/user?tab=purchases");

  const dashboardContent = page.locator("#dashboard-content");
  await expect(dashboardContent.getByText("Purchases & documents", { exact: true })).toBeVisible();

  return dashboardContent;
};

const getPurchaseRow = (dashboardContent, eventName) =>
  dashboardContent.locator("tbody tr", { hasText: eventName });

test.describe("user dashboard purchases", () => {
  test.skip(!E2E_PAYMENTS_ENABLED, "Payments are disabled in this environment.");

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
    const purchaseRow = getPurchaseRow(
      dashboardContent,
      TEST_PAYMENT_EVENT_NAMES.refunds,
    );

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
    await expect(creditNoteAction).toHaveAttribute("target", "_blank");
    await expect(invoiceAction).toHaveAttribute("target", "_blank");
  });

  test("purchase documents are private to their attendee", async ({ emptyUserPage }) => {
    // Request another attendee's documents without following provider redirects.
    const invoiceResponse = await emptyUserPage.request.get(
      buildE2eUrl(
        `/dashboard/user/purchases/${TEST_PURCHASE_DOCUMENT_IDS.purchase}/invoice`,
      ),
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
    const purchaseRow = getPurchaseRow(
      dashboardContent,
      TEST_PAYMENT_EVENT_NAMES.refunds,
    );
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
    const purchaseRow = getPurchaseRow(
      dashboardContent,
      TEST_PAYMENT_EVENT_NAMES.refunds,
    );

    // Verify the completed purchase remains visible with its document state.
    await expect(purchaseRow).toContainText("Paid");
    await purchaseRow
      .getByLabel(`Open document actions for ${TEST_PAYMENT_EVENT_NAMES.refunds}`)
      .click();
    await expect(
      purchaseRow.getByRole("menuitem", { name: "Invoice processing" }),
    ).toBeDisabled();
  });

  test("shows processing and failed credit note states", async ({
    eventsManagerGroupPage,
    organizerGroupWithoutPaymentsPage,
  }) => {
    // Verify an in-flight refund exposes both processing document labels.
    const processingDashboard = await openPurchasesDashboard(
      organizerGroupWithoutPaymentsPage,
    );
    const processingRow = getPurchaseRow(
      processingDashboard,
      TEST_PAYMENT_EVENT_NAMES.refunds,
    );
    await expect(processingRow).toContainText("Refund processing");
    await processingRow
      .getByLabel(`Open document actions for ${TEST_PAYMENT_EVENT_NAMES.refunds}`)
      .click();
    await expect(
      processingRow.getByRole("menuitem", { name: "Credit note processing" }),
    ).toBeDisabled();
    await expect(
      processingRow.getByRole("menuitem", { name: "Invoice processing" }),
    ).toBeDisabled();

    // Verify an exhausted credit-note job is presented for review, not download.
    const failedDashboard = await openPurchasesDashboard(eventsManagerGroupPage);
    const failedRow = getPurchaseRow(
      failedDashboard,
      TEST_PAYMENT_EVENT_NAMES.refunds,
    );
    await failedRow
      .getByLabel(`Open document actions for ${TEST_PAYMENT_EVENT_NAMES.refunds}`)
      .click();
    await expect(
      failedRow.getByRole("menuitem", { name: "Credit note needs review" }),
    ).toBeDisabled();
    await expect(
      failedRow.getByRole("menuitem", { name: "Download credit note" }),
    ).toHaveCount(0);
  });

  test("keeps past and canceled purchases in durable history", async ({
    adminCommunityPage,
  }) => {
    // Open the complete durable history for the seeded administrator.
    const dashboardContent = await openPurchasesDashboard(adminCommunityPage);
    const pastPurchaseRow = getPurchaseRow(
      dashboardContent,
      "Past Event For Filtering",
    );
    const canceledPurchaseRow = getPurchaseRow(
      dashboardContent,
      "Canceled Public Event",
    );

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

  test("purchases table exposes every responsive column", async ({ adminCommunityPage }) => {
    // Open purchases before checking the responsive table contract.
    const dashboardContent = await openPurchasesDashboard(adminCommunityPage);
    const purchasesTable = dashboardContent.getByRole("table");
    const headers = ["Event", "Purchased", "Amount", "Status", "Actions"];

    // Verify compact and wide layouts expose the intended columns.
    await expectTableColumnsAtViewport(
      adminCommunityPage,
      purchasesTable,
      1024,
      ["Event", "Amount", "Status", "Actions"],
      ["Purchased"],
    );
    await expectTableColumnsAtViewport(adminCommunityPage, purchasesTable, 1280, headers, []);
    await expectTableHeaders(purchasesTable, headers);
  });
});
