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

  it("labels the mobile check-in links by their actions", async () => {
    // Load the header template before checking mobile check-in navigation.
    const template = normalizeWhitespace(await loadTemplate());

    // Verify each mobile link describes its attendee action.
    expect(template).to.include(
      'href="/dashboard/user?tab=check-in" hx-boost="true" hx-target="body" class="inline-block w-full text-start px-4 py-2 hover:bg-stone-100" role="menuitem"> <div class="flex items-center"> <div class="svg-icon size-4 icon-events bg-stone-600"></div> <div class="ms-2 text-xs/6">Check in</div>',
    );
    expect(template).to.include(
      'href="/dashboard/group?tab=check-in" hx-boost="true" hx-target="body" class="inline-block w-full text-start px-4 py-2 hover:bg-stone-100" role="menuitem"> <div class="flex items-center"> <div class="svg-icon size-4 icon-qr-code bg-stone-600"></div> <div class="ms-2 text-xs/6">Scan attendees</div>',
    );
  });
});
