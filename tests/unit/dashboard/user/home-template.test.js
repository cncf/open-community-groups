import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/user/home.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

describe("dashboard user home template", () => {
  it("uses the invoice icon for purchases and documents", async () => {
    const template = await loadTemplate();

    expect(template).to.include('menu_item(name = "Purchases & documents", icon = "invoice"');
  });
});
