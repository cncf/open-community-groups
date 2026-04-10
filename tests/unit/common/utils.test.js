import { expect } from "@open-wc/testing";

import {
  isString,
  normalizeUsers,
  sanitizeStringArray,
  setImageFieldValue,
  setSelectValue,
  setTextValue,
  toOptionalString,
  toTrimmedString,
} from "/static/js/common/utils.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("common utils", () => {
  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    resetDom();
  });

  it("normalizes string helpers", () => {
    expect(isString("hello")).to.equal(true);
    expect(isString(42)).to.equal(false);
    expect(toTrimmedString("  hello  ")).to.equal("hello");
    expect(toTrimmedString(null)).to.equal("");
    expect(toOptionalString(42)).to.equal("42");
    expect(toOptionalString(undefined)).to.equal("");
  });

  it("sanitizes string arrays and normalizes users", () => {
    expect(sanitizeStringArray([" alpha ", "", " beta ", null])).to.deep.equal(["alpha", "beta"]);

    expect(
      normalizeUsers([
        { user: { user_id: "1", username: "alice" } },
        { user_id: "2", username: "bob" },
        { username: "carol" },
        { foo: "bar" },
      ]),
    ).to.deep.equal([
      { user_id: "1", username: "alice" },
      { user_id: "2", username: "bob" },
      { username: "carol" },
    ]);
  });

  it("sets text inputs and dispatches input events", () => {
    document.body.innerHTML = `<input id="title" value="" />`;

    const input = document.getElementById("title");
    const values = [];

    input.addEventListener("input", () => {
      values.push(input.value);
    });

    setTextValue("title", "Community Call");
    setTextValue("title", null);

    expect(input.value).to.equal("");
    expect(values).to.deep.equal(["Community Call", ""]);
  });

  it("sets select values only when the option exists", () => {
    document.body.innerHTML = `
      <select id="category_id">
        <option value="">Select one</option>
        <option value="talk">Talk</option>
        <option value="workshop">Workshop</option>
      </select>
    `;

    const select = document.getElementById("category_id");
    const changes = [];

    select.addEventListener("change", () => {
      changes.push(select.value);
    });

    setSelectValue("category_id", "workshop");
    setSelectValue("category_id", "unknown");

    expect(select.value).to.equal("");
    expect(changes).to.deep.equal(["workshop", ""]);
  });

  it("uses the image field setter when available and falls back to value updates", () => {
    document.body.innerHTML = `
      <image-field name="cover"></image-field>
      <image-field name="avatar"></image-field>
    `;

    const coverField = document.querySelector('image-field[name="cover"]');
    const avatarField = document.querySelector('image-field[name="avatar"]');

    let coverValue = "";
    let avatarUpdates = 0;

    coverField._setValue = (value) => {
      coverValue = value;
    };
    avatarField.requestUpdate = () => {
      avatarUpdates += 1;
    };

    setImageFieldValue("cover", "https://example.com/cover.png");
    setImageFieldValue("avatar", "https://example.com/avatar.png");

    expect(coverValue).to.equal("https://example.com/cover.png");
    expect(avatarField.value).to.equal("https://example.com/avatar.png");
    expect(avatarUpdates).to.equal(1);
  });
});
