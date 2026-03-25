import { expect } from "@open-wc/testing";

import { passwordsMatch, trimmedNonEmpty } from "/static/js/common/validators.js";

describe("validators", () => {
  it("rejects empty and whitespace-only values", () => {
    expect(trimmedNonEmpty("")).to.equal("Value cannot be empty");
    expect(trimmedNonEmpty("   ")).to.equal("Value cannot be empty");
    expect(trimmedNonEmpty("Open Community Groups")).to.equal(null);
  });

  it("validates password confirmation matches", () => {
    expect(passwordsMatch("secret", "different")).to.equal("Passwords do not match");
    expect(passwordsMatch("secret", "secret")).to.equal(null);
  });
});
