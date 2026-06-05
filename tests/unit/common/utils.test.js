import { expect } from "@open-wc/testing";

import {
  isString,
  normalizeUsers,
  parseJsonAttribute,
  parseJsonText,
  sanitizeStringArray,
  setImageFieldValue,
  setSelectValue,
  setTextValue,
  toBoolean,
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
    // String checks distinguish strings from other primitive values.
    expect(isString("hello")).to.equal(true);
    expect(isString(42)).to.equal(false);

    // Verify trimming and optional string conversion helpers.
    expect(toTrimmedString("  hello  ")).to.equal("hello");
    expect(toTrimmedString(null)).to.equal("");
    expect(toOptionalString(42)).to.equal("42");
    expect(toOptionalString(undefined)).to.equal("");
  });

  it("parses JSON attributes safely and normalizes booleans", () => {
    // JSON attributes accept strings and already-parsed values.
    expect(parseJsonAttribute("[1,2,3]", [])).to.deep.equal([1, 2, 3]);
    expect(parseJsonAttribute([{ id: 1 }], [])).to.deep.equal([{ id: 1 }]);
    expect(parseJsonAttribute({ zoom: 100 }, {})).to.deep.equal({ zoom: 100 });
    expect(parseJsonAttribute({ day_1: [{ id: 1 }] }, [])).to.deep.equal({
      day_1: [{ id: 1 }],
    });
    expect(parseJsonAttribute("not-json", ["fallback"])).to.deep.equal([
      "fallback",
    ]);
    expect(parseJsonAttribute("", ["fallback"])).to.deep.equal(["fallback"]);

    // Boolean values are normalized from booleans and strings.
    expect(toBoolean(true)).to.equal(true);
    expect(toBoolean(" TRUE ")).to.equal(true);
    expect(toBoolean("false")).to.equal(false);
    expect(toBoolean("maybe", true)).to.equal(true);
  });

  it("parses JSON text safely", () => {
    // JSON text parses into the expected value.
    expect(parseJsonText('{"ready":true}', null)).to.deep.equal({ ready: true });

    // Invalid JSON returns the fallback and reports the parse error.
    const errors = [];
    expect(parseJsonText("not-json", { fallback: true }, (error) => errors.push(error))).to.deep.equal({
      fallback: true,
    });
    expect(errors).to.have.length(1);

    // Empty JSON text returns the fallback without reporting an error.
    expect(parseJsonText("", [])).to.deep.equal([]);
  });

  it("sanitizes string arrays and normalizes users", () => {
    // Assert the sanitize string array.
    expect(sanitizeStringArray([" alpha ", "", " beta ", null])).to.deep.equal([
      "alpha",
      "beta",
    ]);

    // Assert the updated value.
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
    // Build the DOM fixture with title.
    document.body.innerHTML = `<input id="title" value="" />`;

    // Collect the input and values elements.
    const input = document.getElementById("title");
    const values = [];

    // Listen for the emitted event.
    input.addEventListener("input", () => {
      values.push(input.value);
    });

    // Set and clear the text input through the helper.
    setTextValue("title", "Community Call");
    setTextValue("title", null);

    // The helper emits input events and clears null text values.
    expect(input.value).to.equal("");
    expect(values).to.deep.equal(["Community Call", ""]);
  });

  it("sets select values only when the option exists", () => {
    // Build the DOM fixture with category id.
    document.body.innerHTML = `
      <select id="category_id">
        <option value="">Select one</option>
        <option value="talk">Talk</option>
        <option value="workshop">Workshop</option>
      </select>
    `;

    // Track the select value and emitted change events.
    const select = document.getElementById("category_id");
    const changes = [];

    // Listen for the emitted event.
    select.addEventListener("change", () => {
      changes.push(select.value);
    });

    // Select a valid option and clear invalid values through the helper.
    setSelectValue("category_id", "workshop");
    setSelectValue("category_id", "unknown");

    // Invalid values clear the select after the valid change fires.
    expect(select.value).to.equal("");
    expect(changes).to.deep.equal(["workshop", ""]);
  });

  it("uses the image field setter when available and falls back to value updates", () => {
    // Build the DOM fixture with image-field.
    document.body.innerHTML = `
      <image-field name="cover"></image-field>
      <image-field name="avatar"></image-field>
    `;

    // Read the two image fields that use different update paths.
    const coverField = document.querySelector('image-field[name="cover"]');
    const avatarField = document.querySelector('image-field[name="avatar"]');

    // Track setter and requestUpdate calls from image-field helpers.
    let coverValue = "";
    let avatarUpdates = 0;

    // Make one field use its setter and the other fall back to value updates.
    coverField._setValue = (value) => {
      coverValue = value;
    };
    avatarField.requestUpdate = () => {
      avatarUpdates += 1;
    };

    // Update image fields through their setter or value fallback.
    setImageFieldValue("cover", "https://example.com/cover.png");
    setImageFieldValue("avatar", "https://example.com/avatar.png");

    // Setter and fallback updates both store the requested image values.
    expect(coverValue).to.equal("https://example.com/cover.png");
    expect(avatarField.value).to.equal("https://example.com/avatar.png");
    expect(avatarUpdates).to.equal(1);
  });
});
