import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch(
    "/ocg-server/templates/dashboard/user/home.html",
  );

  expect(response.ok).to.equal(true);

  return response.text();
};

describe("dashboard user home template", () => {
  it("uses a compact purchases label through the large breakpoint", async () => {
    // Load the user dashboard shell before checking responsive navigation copy.
    const template = await loadTemplate();

    // Verify the item keeps its full label, compact fallback, and invoice icon.
    expect(template).to.include(
      'menu_item(name = "Purchases & documents", compact_name = "Purchases", icon = "invoice"',
    );
  });
});
