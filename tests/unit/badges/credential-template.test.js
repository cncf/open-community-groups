import { expect } from "@open-wc/testing";

describe("badge credential template", () => {
  it("renders the badge description and issuer", async () => {
    const response = await fetch("/ocg-server/templates/badges/credential.html");

    expect(response.ok).to.equal(true);
    const template = await response.text();
    expect(template).to.include(
      '<p class="mt-6 text-stone-700">{{ award.snapshot.description }}</p>',
    );
    expect(template).to.include(
      "{{ award.snapshot.issuer.group_name }} ({{ award.snapshot.issuer.community_name }})",
    );
  });
});
