import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/group/home.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard group home template", () => {
  it("loads the shared user profile modal wiring", async () => {
    // Load the group dashboard shell template before checking profile modal wiring.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the dashboard shell loads one trigger module and one modal component.
    expect(template).to.include('src="/static/js/common/users/user-profile-modal-triggers.js"');
    expect(template).to.include(
      '<script type="module" src="/static/js/common/modals/user-info-modal.js"></script>',
    );
    expect(template).to.include("<user-info-modal></user-info-modal>");
  });
});
