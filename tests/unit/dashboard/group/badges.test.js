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
    // Render the initialized badge controls and locate the revoke dialog.
    const root = fixture();
    const dialog = root.querySelector("#badge-revoke-one");

    // Open the dialog through its declarative trigger.
    root.querySelector('[data-badge-dialog-open="badge-revoke-one"]').click();
    expect(dialog.open).to.equal(true);

    // Close the dialog through its declarative control.
    dialog.querySelector("[data-badge-dialog-close]").click();
    expect(dialog.open).to.equal(false);
  });

  /** Dispatches the bubbling HTMX response event that a form receives before its alert. */
  const dispatchBeforeOnLoad = (form, status) => {
    form.dispatchEvent(
      new CustomEvent("htmx:beforeOnLoad", {
        bubbles: true,
        detail: { xhr: { status, getResponseHeader: () => null } },
      }),
    );
  };

  it("closes the open dialog when its form succeeds", () => {
    // Open the revoke dialog through its declarative trigger.
    const root = fixture();
    const dialog = root.querySelector("#badge-revoke-one");
    root.querySelector('[data-badge-dialog-open="badge-revoke-one"]').click();

    dispatchBeforeOnLoad(dialog.querySelector("form"), 201);

    // Assert the dialog closes so the success alert renders on the page.
    expect(dialog.open).to.equal(false);
  });

  it("keeps the dialog open when its form fails", () => {
    // Open the revoke dialog through its declarative trigger.
    const root = fixture();
    const dialog = root.querySelector("#badge-revoke-one");
    root.querySelector('[data-badge-dialog-open="badge-revoke-one"]').click();

    dispatchBeforeOnLoad(dialog.querySelector("form"), 422);

    // Assert the dialog stays open so the error alert renders inside it.
    expect(dialog.open).to.equal(true);
  });

  it("adds the uploaded badge filename to the declarative artwork form", () => {
    // Render the artwork form with an uploaded badge image value.
    const root = fixture();
    root.querySelector('image-field[target="badge"]').value = "/images/badges/content-addressed.png";

    root
      .querySelector("[data-artwork-form]")
      .dispatchEvent(new SubmitEvent("submit", { bubbles: true, cancelable: true }));

    // Verify submission copies only the stored filename into the hidden field.
    expect(root.querySelector("[data-artwork-file-name]").value).to.equal("content-addressed.png");
  });
});
