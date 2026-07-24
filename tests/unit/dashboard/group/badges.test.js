import { expect, waitUntil } from "@open-wc/testing";

import { initializeGroupBadges } from "/static/js/dashboard/group/badges.js";

describe("group dashboard badges", () => {
  let originalFetch;
  let originalHtmx;
  let originalSwal;

  beforeEach(() => {
    originalFetch = window.fetch;
    originalHtmx = window.htmx;
    originalSwal = window.Swal;
  });

  afterEach(() => {
    document.querySelector("[data-group-badges]")?.remove();
    document.getElementById("dashboard-content")?.remove();
    window.fetch = originalFetch;
    window.htmx = originalHtmx;
    window.Swal = originalSwal;
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
        <button type="button" data-badge-revoke data-name="Participant" data-endpoint="/dashboard/group/badges/awards/one/revoke">Revoke</button>
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

  it("requires a private reason, prevents duplicate revocation, and refreshes awards", async () => {
    const { dashboard, root } = fixture();
    const triggers = [];
    const requests = [];
    window.htmx = {
      trigger: (target, name) => triggers.push({ target, name }),
    };
    window.Swal = {
      fire: async (options) =>
        options.input === "textarea" ? { isConfirmed: true, value: "Policy violation" } : {},
      showValidationMessage() {},
    };
    window.fetch = async (url, options) => {
      requests.push({ url: String(url), options });
      return new Response(null, { status: 204 });
    };
    const button = root.querySelector("[data-badge-revoke]");

    button.click();
    button.click();
    await waitUntil(
      () => dashboard.getAttribute("hx-get") === "/dashboard/group/badges?pane=awards",
      "award history should refresh after revocation",
    );

    expect(requests).to.have.length(1);
    expect(requests[0].options.body.toString()).to.equal("reason=Policy+violation");
    expect(button.disabled).to.equal(true);
    expect(dashboard.getAttribute("hx-get")).to.equal("/dashboard/group/badges?pane=awards");
    expect(triggers[0]).to.deep.include({
      target: dashboard,
      name: "refresh-group-dashboard-table",
    });
  });

  it("preserves a revocation action after a recoverable server error", async () => {
    const { root } = fixture();
    window.htmx = { trigger() {} };
    window.Swal = {
      fire: async (options) => (options.input === "textarea" ? { isConfirmed: true, value: "Reason" } : {}),
      showValidationMessage() {},
    };
    window.fetch = async () => new Response("Temporary failure", { status: 500 });
    const button = root.querySelector("[data-badge-revoke]");

    button.click();
    await waitUntil(
      () => button.dataset.revokePending === undefined,
      "a failed revocation should become actionable again",
    );

    expect(button.disabled).to.equal(false);
    expect(button.isConnected).to.equal(true);
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
