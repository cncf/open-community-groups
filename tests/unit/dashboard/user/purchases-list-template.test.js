import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch(
    "/ocg-server/templates/dashboard/user/purchases_list.html",
  );

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard user purchases list template", () => {
  it("uses the responsive document table layout", async () => {
    // Load the purchases list template before checking the document action layout.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify horizontal scrolling stops once the dashboard table has enough room.
    expect(template).to.include(
      '<div class="relative overflow-x-auto lg:overflow-x-visible">',
    );

    // Verify compact rows show purchase time below the event until the xl layout.
    expect(template).to.include(
      '<th scope="col" class="hidden px-3 py-3 xl:table-cell xl:px-5">Purchased</th>',
    );
    expect(template).to.include(
      '<td class="hidden whitespace-nowrap px-3 py-4 xl:table-cell xl:px-5">',
    );
    expect(template).to.include(
      'class="mt-0.5 text-xs font-normal text-stone-500 xl:hidden"',
    );
    expect(template).to.include('format("%b %d, %Y at %H:%M UTC")');

    // Verify the empty state spans only the columns visible at each breakpoint.
    expect(template).to.include(
      '<td class="px-8 py-20 text-center lg:hidden" colspan="3">',
    );
    expect(template).to.include(
      '<td class="hidden px-8 py-20 text-center lg:table-cell xl:hidden" colspan="4">',
    );
    expect(template).to.include(
      '<td class="hidden px-8 py-20 text-center xl:table-cell" colspan="5">',
    );

    // Verify the compact actions column has an accessible-only heading.
    expect(template).to.include(
      '<th scope="col" class="w-[72px] px-3 py-3 text-right xl:px-5"> <span class="sr-only">Actions</span> </th>',
    );
    expect(template).to.include(
      '<td class="w-[72px] px-3 py-4 text-right xl:px-5">',
    );
  });

  it("uses payment-specific status colors and localized amounts", async () => {
    // Load the purchases list before checking payment presentation helpers.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify statuses share the payment palette and amounts are localized.
    expect(template.match(/badges::payment_status_badge/g)).to.have.length(2);
    expect(template).to.include(
      "<span data-localized-currency>{{ purchase.formatted_amount() }}</span>",
    );
    expect(template).to.not.include("badges::status_badge");
  });

  it("marks externally managed purchases with a shared badge", async () => {
    // Load the purchases list before checking external-payment presentation.
    const template = normalizeWhitespace(await loadTemplate());

    expect(template).to.include("{% if purchase.externally_managed -%}");
    expect(template).to.include(
      'badges::common_badge(content = "Externally managed", extra_styles = Some("border-stone-200 bg-stone-50 px-2.5 py-0.5 text-stone-700"))',
    );
    expect(template.match(/Externally managed/g)).to.have.lengthOf(2);
    expect(template).to.include("<span>Managed outside OCG</span>");
  });

  it("renders invoice and credit note actions in a labelled dropdown", async () => {
    // Load the purchases list template before checking the document actions.
    const template = normalizeWhitespace(await loadTemplate());
    const downloadIconPosition = template.indexOf(
      'class="svg-icon size-4 icon-refund-download shrink-0 bg-stone-600"',
    );
    const invoiceIconPosition = template.indexOf(
      'class="svg-icon size-4 icon-invoice shrink-0 bg-stone-600"',
    );

    // Verify the shared three-dot menu exposes an accessible document trigger.
    expect(template).to.include(
      '<details data-actions-menu class="group relative inline-flex justify-end">',
    );
    expect(template).to.include(
      'aria-label="Open document actions for {{ purchase.event_name }}"',
    );
    expect(template).to.include(
      'class="svg-icon size-4 icon-vertical-dots" aria-hidden="true"',
    );
    expect(template).to.include('<ul class="text-sm text-stone-700" role="menu">');

    // Verify each document action keeps its icon, label, and pending state.
    expect(template).to.include(
      'class="svg-icon size-4 icon-refund-download shrink-0 bg-stone-600" aria-hidden="true">',
    );
    expect(template).to.include("<span>Download credit note</span>");
    expect(template).to.include(
      'class="svg-icon size-4 icon-invoice shrink-0 bg-stone-600" aria-hidden="true">',
    );
    expect(template).to.include("<span>View invoice</span>");
    expect(template.match(/aria-disabled="true"/g)).to.have.lengthOf(2);
    expect(template.match(/role="menuitem"/g)).to.have.lengthOf(4);
    expect(template).to.include("<span>Invoice processing</span>");
    expect(downloadIconPosition).to.be.lessThan(invoiceIconPosition);
  });
});
