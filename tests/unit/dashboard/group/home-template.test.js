import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/group/home.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("dashboard group home template", () => {
  it("uses the shared dashboard menu shell", async () => {
    // Load the group dashboard shell template before checking menu layout.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify the group shell delegates shared title, spinner, and wrapper markup.
    expect(template).to.include(
      'dashboard::dashboard_menu_shell("Group Dashboard", spinner_classes = "hx-spinner -mt-0.5 relative")',
    );
    expect(template).not.to.include('id="dashboard-spinner" class="hx-spinner -mt-0.5 relative"');
    expect(template).not.to.include("max-h-full w-full flex flex-col flex-1");
  });

  it("keeps dashboard content at full minimum height", async () => {
    // Load the group dashboard shell template before checking content layout.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify swapped dashboard content can fill the dashboard card.
    expect(template).to.include('id="dashboard-content"');
    expect(template).to.include(
      'class="flex min-h-full min-h-[calc(100dvh-7.5rem)] flex-col p-4 sm:p-6 lg:p-12"',
    );
  });

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
