import { expect } from "@open-wc/testing";

const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/common/header.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

describe("common header template", () => {
  it("exposes logged-in profile completion state on the user menu button", async () => {
    // Load the header template before checking user menu data markers.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify public pages can read the backend profile completion flag.
    expect(template).to.include('id="user-dropdown-button"');
    expect(template).to.include('data-logged-in="true"');
    expect(template).to.include('data-profile-complete="{{ user.profile_complete }}"');
  });
});
