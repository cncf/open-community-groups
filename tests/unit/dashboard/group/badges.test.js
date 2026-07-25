import { expect } from "@open-wc/testing";

import { initializeGroupBadges } from "/static/js/dashboard/group/badges.js";

describe("group dashboard badges", () => {
  afterEach(() => {
    document.querySelector("[data-group-badges]")?.remove();
  });

  const fixture = () => {
    const root = document.createElement("section");
    root.dataset.groupBadges = "";
    root.innerHTML = `
      <button type="button" data-badge-dialog-open="badge-revoke-one">Revoke</button>
      <dialog id="badge-revoke-one">
        <form>
          <textarea name="reason"></textarea>
          <button type="button" data-badge-dialog-close>Cancel</button>
          <button type="submit">Permanently revoke</button>
        </form>
      </dialog>
      <form data-artwork-form>
        <image-field target="badge"></image-field>
        <input type="hidden" data-artwork-file-name>
        <button type="submit">Add artwork</button>
      </form>`;
    document.body.append(root);
    initializeGroupBadges(root);
    return root;
  };

  it("opens and closes a badge dialog", () => {
    const root = fixture();
    const dialog = root.querySelector("#badge-revoke-one");

    root.querySelector('[data-badge-dialog-open="badge-revoke-one"]').click();
    expect(dialog.open).to.equal(true);

    dialog.querySelector("[data-badge-dialog-close]").click();
    expect(dialog.open).to.equal(false);
  });

  it("adds the uploaded badge filename to the declarative artwork form", () => {
    const root = fixture();
    root.querySelector('image-field[target="badge"]').value = "/images/badges/content-addressed.png";

    root
      .querySelector("[data-artwork-form]")
      .dispatchEvent(new SubmitEvent("submit", { bubbles: true, cancelable: true }));

    expect(root.querySelector("[data-artwork-file-name]").value).to.equal("content-addressed.png");
  });
});
