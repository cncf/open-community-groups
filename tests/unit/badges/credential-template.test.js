import { expect } from "@open-wc/testing";

describe("badge credential template", () => {
  it("renders the badge description without exposing it in share metadata", async () => {
    // Load the public credential template.
    const response = await fetch("/ocg-server/templates/badges/credential.html");

    // Verify visible issuer details remain separate from social metadata.
    expect(response.ok).to.equal(true);
    const template = await response.text();
    expect(template).to.include('<p class="mt-6 text-stone-700">{{ award.snapshot.description }}</p>');
    expect(template).to.include(
      'format!("{} ({})", self.award.snapshot.issuer.group_name, self.award.snapshot.issuer.community_name)',
    );
    expect(template.match(/description = &share_description/gu)).to.have.length(2);
    expect(template).to.include("{% block twitter_meta -%}");
    expect(template).to.not.include("description = &award.snapshot.description");
    expect(template).to.include(
      "{{ award.snapshot.issuer.group_name }} ({{ award.snapshot.issuer.community_name }})",
    );
  });
});
