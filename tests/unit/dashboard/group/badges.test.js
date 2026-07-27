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

  it("gives badge artwork options a comfortable inset", async () => {
    // Load the badge definition template.
    const response = await fetch("/ocg-server/templates/dashboard/group/badges.html");

    // Verify selectable artwork uses the intended inset.
    expect(response.ok).to.equal(true);
    expect(await response.text()).to.include(
      'class="block rounded-xl border border-stone-200 bg-white p-2.5 transition',
    );
  });

  it("uses larger saved artwork cards with hover delete controls", async () => {
    // Load the saved artwork gallery template.
    const response = await fetch("/ocg-server/templates/dashboard/group/badges_artwork.html");

    // Verify gallery sizing and hover-revealed delete controls.
    expect(response.ok).to.equal(true);
    const template = await response.text();
    expect(template).to.include("lg:grid-cols-5 xl:grid-cols-7");
    expect(template).to.include(
      'class="group relative overflow-hidden rounded-lg border border-stone-200 bg-white p-3"',
    );
    expect(template).to.include(
      "btn-tertiary absolute right-2 top-2 p-2 opacity-0 transition-opacity group-hover:opacity-100 group-focus-within:opacity-100",
    );
    expect(template).to.include('class="svg-icon size-4 icon-trash"');
  });

  it("uses a compact badge column and wraps badge names to two lines", async () => {
    // Load the badge definition list template.
    const response = await fetch("/ocg-server/templates/dashboard/group/badges.html");

    // Verify the fixed table layout constrains and wraps badge names.
    expect(response.ok).to.equal(true);
    const template = await response.text();

    expect(template).to.include("table-fixed");
    expect(template).to.include("xl:w-[35%]");
    expect(template).to.include('class="line-clamp-2 break-words font-medium text-stone-900"');
  });

  it("keeps badge dialog heading IDs aligned with their aria labels", async () => {
    // Load the group badge template that contains both dialog variants.
    const response = await fetch("/ocg-server/templates/dashboard/group/badges.html");

    // The template remains available to dashboard pages.
    expect(response.ok).to.equal(true);
    const template = await response.text();

    // Each dialog label points at a heading ID rendered by its corresponding form.
    expect(template).to.include('aria-labelledby="badge-edit-{{ badge.badge_id }}-title"');
    expect(template).to.include('aria-labelledby="badge-add-title"');
    expect(template).to.include('id="badge-edit-{{ id }}-title"');
    expect(template).to.include('id="badge-add-title"');
  });
});
