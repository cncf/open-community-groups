import { expect } from "@open-wc/testing";

import { initializeGroupBadges } from "/static/js/dashboard/group/badges.js";

describe("group dashboard badges", () => {
  afterEach(() => {
    document.querySelector("[data-group-badges]")?.remove();
    document.getElementById("dashboard-content")?.remove();
  });

  const fixture = () => {
    const dashboard = document.createElement("div");
    dashboard.id = "dashboard-content";
    dashboard.setAttribute("hx-get", "/dashboard/group/badges");
    const root = document.createElement("section");
    root.dataset.groupBadges = "";
    root.dataset.initialPane = "awards";
    root.innerHTML = `
      <select data-badge-pane-select><option value="definitions">Badges</option><option value="awards">Awards</option></select>
      <button type="button" data-badge-pane-button="definitions"></button>
      <button type="button" data-badge-pane-button="awards"></button>
      <section data-content="definitions"></section>
      <section data-content="awards">
        <button type="button" data-badge-dialog-open="badge-revoke-one">Revoke</button>
        <dialog id="badge-revoke-one">
          <form data-badge-refresh-pane="awards">
            <textarea name="reason"></textarea>
            <button type="button" data-badge-dialog-close>Cancel</button>
            <button type="submit">Permanently revoke</button>
          </form>
        </dialog>
      </section>
      <section data-content="artwork">
        <form data-artwork-form data-badge-refresh-pane="artwork">
          <image-field target="badge"></image-field>
          <input type="hidden" data-artwork-file-name>
          <button type="submit">Add artwork</button>
        </form>
      </section>`;
    document.body.append(dashboard, root);
    initializeGroupBadges(root);
    return { dashboard, root };
  };

  it("honors the server-selected pane and switches with keyboard-operable controls", () => {
    const { root } = fixture();

    expect(root.querySelector('[data-content="awards"]').hidden).to.equal(false);
    expect(root.querySelector('[data-content="definitions"]').hidden).to.equal(true);
    const definitions = root.querySelector('[data-badge-pane-button="definitions"]');
    definitions.click();

    expect(root.querySelector('[data-content="definitions"]').hidden).to.equal(false);
    expect(definitions.getAttribute("aria-selected")).to.equal("true");
    expect(definitions.tabIndex).to.equal(0);

    definitions.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "ArrowDown" }));
    const awards = root.querySelector('[data-badge-pane-button="awards"]');
    expect(awards.getAttribute("aria-selected")).to.equal("true");
    expect(document.activeElement).to.equal(awards);
  });

  it("opens and closes the revoke dialog and targets the awards pane on submit", () => {
    const { dashboard, root } = fixture();
    const dialog = root.querySelector("#badge-revoke-one");

    root.querySelector('[data-badge-dialog-open="badge-revoke-one"]').click();
    expect(dialog.open).to.equal(true);

    dialog
      .querySelector("form")
      .dispatchEvent(new SubmitEvent("submit", { bubbles: true, cancelable: true }));
    expect(dashboard.getAttribute("hx-get")).to.equal("/dashboard/group/badges?pane=awards");

    dialog.querySelector("[data-badge-dialog-close]").click();
    expect(dialog.open).to.equal(false);
  });

  it("adds the uploaded badge filename to the declarative artwork form", () => {
    const { dashboard, root } = fixture();
    root.querySelector('image-field[target="badge"]').value = "/images/badges/content-addressed.png";

    root
      .querySelector("[data-artwork-form]")
      .dispatchEvent(new SubmitEvent("submit", { bubbles: true, cancelable: true }));

    expect(root.querySelector("[data-artwork-file-name]").value).to.equal("content-addressed.png");
    expect(dashboard.getAttribute("hx-get")).to.equal("/dashboard/group/badges?pane=artwork");
  });
});
