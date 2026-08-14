import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/user/purchases_list.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard user purchases list template", () => {
  it("uses the responsive document table layout", async () => {
    // Load the purchases list template before checking the document action layout.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the date hides and horizontal scrolling stops at the dashboard breakpoint.
    expect(template).to.include('<div class="relative overflow-x-auto lg:overflow-x-visible">');
    expect(template).to.include(
      '<th scope="col" class="hidden px-3 py-3 xl:table-cell xl:px-5">Purchased</th>',
    );
    expect(template).to.include('<td class="hidden whitespace-nowrap px-3 py-4 xl:table-cell xl:px-5">');

    // Verify the empty state spans only the columns visible at each breakpoint.
    expect(template).to.include('<td class="px-8 py-20 text-center lg:hidden" colspan="3">');
    expect(template).to.include(
      '<td class="hidden px-8 py-20 text-center lg:table-cell xl:hidden" colspan="4">',
    );
    expect(template).to.include('<td class="hidden px-8 py-20 text-center xl:table-cell" colspan="5">');

    // Verify the document column keeps space for two right-aligned actions.
    expect(template).to.include(
      '<th scope="col" class="w-[112px] px-3 py-3 text-right xl:px-5">Documents</th>',
    );
    expect(template).to.include(
      '<td class="w-[112px] px-3 py-4 text-right xl:px-5"> <div class="flex items-center justify-end gap-2">',
    );
  });

  it("renders labelled invoice and credit note icon actions", async () => {
    // Load the purchases list template before checking the document actions.
    const template = normalizeWhitespace(await loadTemplate());
    const downloadIconPosition = template.indexOf("icon-download");
    const viewIconPosition = template.indexOf("icon-eye");

    // Verify both actions are labelled and the download precedes the view action.
    expect(template).to.include('aria-label="View invoice" title="View invoice"');
    expect(template).to.include('class="svg-icon size-4 icon-eye" aria-hidden="true"');
    expect(template).to.include('aria-label="Download credit note" title="Download credit note"');
    expect(template).to.include('class="svg-icon size-4 icon-download" aria-hidden="true"');
    expect(downloadIconPosition).to.be.lessThan(viewIconPosition);
  });
});
