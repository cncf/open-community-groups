import { expect } from "@open-wc/testing";

describe("dashboard alliance groups add template", () => {
  it("uses a city, state, and country location search prompt", async () => {
    // Load the group creation template to verify the location search copy.
    const response = await fetch("/ocg-server/templates/dashboard/alliance/groups_add.html");
    const template = await response.text();

    // The create form should match the update form's broader location search behavior.
    expect(template).to.include('placeholder-text="Search for a city, state, country..."');
    expect(template).to.include('country-name-field-name="country_name"');
    expect(template).to.include('country-code-field-name="country_code"');
  });
});
