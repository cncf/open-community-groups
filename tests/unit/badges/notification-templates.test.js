import { expect } from "@open-wc/testing";

const loadTemplate = async (name) => {
  const response = await fetch(`/ocg-server/templates/notifications/${name}.html`);

  expect(response.ok).to.equal(true);

  return response.text();
};

describe("badge notification templates", () => {
  it("uses badge notification typography and issuer copy", async () => {
    // Load both badge notification templates.
    const [awardedTemplate, revokedTemplate] = await Promise.all([
      loadTemplate("badge_awarded"),
      loadTemplate("badge_revoked"),
    ]);
    const templates = [awardedTemplate, revokedTemplate];

    // Verify badge copy identifies its issuing group.
    templates.forEach((template) => {
      const normalizedTemplate = template.replace(/\s+/gu, " ");

      expect(template).not.to.include('class="default group');
      expect(template).not.to.include('class="default big');
      expect(normalizedTemplate).to.include("badge issued by <strong>");
      expect(normalizedTemplate).to.include("on <strong>Open Community Groups</strong>");
    });

    // Verify only the congratulations line uses the modestly larger font size.
    expect(awardedTemplate).to.include('<p class="default mb-15" style="font-size: 16px">');
    expect(revokedTemplate).not.to.include('style="font-size: 16px"');
  });
});
