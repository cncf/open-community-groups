import { expect } from "@open-wc/testing";

import { registerHtmxResponseHandlers } from "/static/js/common/htmx-extensions.js";
import "/static/js/dashboard/user/notification-group-mutes.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { dispatchHtmxAfterSwap, dispatchHtmxBeforeOnLoad } from "/tests/unit/test-utils/htmx.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

const GROUPS = [
  {
    community_display_name: "Cloud Native Community",
    group_id: "group-1",
    logo_url: "",
    name: "Kubernetes Group",
  },
  {
    community_display_name: "Security Community",
    group_id: "group-2",
    logo_url: "",
    name: "Falco Group",
  },
];

/**
 * Mounts a notification group mutes element and returns it after render.
 * @param {string} [attrs=""] Extra component attributes.
 * @returns {Promise<HTMLElement>} Mounted component.
 */
const mountGroupMutes = async (attrs = "") => {
  document.body.innerHTML = `
    <p id="notification-group-mutes-legend">Only matching groups are listed.</p>
    <notification-group-mutes
      options-url="/dashboard/user/notifications/group-options"
      described-by="notification-group-mutes-legend"
      ${attrs}
    ></notification-group-mutes>
  `;
  const element = document.querySelector("notification-group-mutes");
  await element.updateComplete;
  return element;
};

/**
 * Focuses the search input to load options and waits for rendering.
 * @param {HTMLElement} element Mounted component.
 * @returns {Promise<HTMLInputElement>} Search input.
 */
const loadOptions = async (element) => {
  const search = element.querySelector("#notification-group-mute-search");
  search.focus();
  await waitForMicrotask();
  await element.updateComplete;
  await waitForMicrotask();
  await element.updateComplete;
  return search;
};

/**
 * Returns a fresh JSON response with the default group options.
 * @returns {Response} Group options response.
 */
const optionsResponse = () => new Response(JSON.stringify(GROUPS), { status: 200 });

/**
 * Emulates SweetAlert2 focusing its button, then restoring prior focus when
 * the button is clicked.
 * @returns {{close: Function}} Controls for closing the open alert.
 */
const emulateSwalFocusReturn = () => {
  const fire = globalThis.Swal.fire;
  let closeAlert = () => {};

  globalThis.Swal.fire = (options) => {
    const previousActiveElement = document.activeElement;
    const confirmButton = document.createElement("button");
    confirmButton.type = "button";
    document.body.append(confirmButton);
    confirmButton.focus();
    closeAlert = () => {
      confirmButton.focus();
      confirmButton.remove();
      previousActiveElement?.focus();
    };
    return fire(options);
  };

  return {
    close: () => closeAlert(),
  };
};

describe("notification group mutes", () => {
  const env = useDashboardTestEnv({
    path: "/dashboard/user",
    withHtmx: true,
    withSwal: true,
  });

  afterEach(() => {
    resetDom();
  });

  it("loads options once and exposes an accessible combobox", async () => {
    const fetchMock = mockFetch({ impl: () => optionsResponse() });

    try {
      // Render the component and focus the search twice.
      const element = await mountGroupMutes();
      const search = await loadOptions(element);
      search.blur();
      search.focus();
      await waitForMicrotask();
      await element.updateComplete;

      // Verify options were cached and the input has the expected combobox contract.
      expect(fetchMock.calls).to.have.length(1);
      expect(search.getAttribute("role")).to.equal("combobox");
      expect(search.getAttribute("aria-describedby")).to.equal("notification-group-mutes-legend");
      expect(search.getAttribute("aria-controls")).to.equal("notification-group-mute-options");
      expect(element.querySelectorAll('[role="option"]')).to.have.length(2);
    } finally {
      fetchMock.restore();
    }
  });

  it("filters options by group or community name", async () => {
    const fetchMock = mockFetch({ impl: () => optionsResponse() });

    try {
      // Render and load the options.
      const element = await mountGroupMutes();
      const search = await loadOptions(element);

      // Filter by group name.
      search.value = "falco";
      search.dispatchEvent(new Event("input", { bubbles: true }));
      await element.updateComplete;
      const [filteredOption] = element.querySelectorAll('[role="option"]');
      expect(element.querySelectorAll('[role="option"]')).to.have.length(1);
      expect(filteredOption.textContent).to.include("Falco Group");
      expect(filteredOption.textContent).to.include("Security Community");

      // Filter by community name.
      search.value = "cloud native";
      search.dispatchEvent(new Event("input", { bubbles: true }));
      await element.updateComplete;
      expect(element.querySelector('[role="option"]')?.textContent).to.include("Kubernetes Group");
    } finally {
      fetchMock.restore();
    }
  });

  it("selects with the keyboard, sends PUT, refreshes the list, and invalidates options", async () => {
    const fetchMock = mockFetch({
      impl: (_url, init = {}) => (init.method === "PUT" ? new Response(null, { status: 204 }) : optionsResponse()),
    });

    try {
      // Render and load the options.
      const element = await mountGroupMutes();
      const search = await loadOptions(element);

      // Select the first option with ArrowDown and Enter.
      search.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "ArrowDown" }));
      await element.updateComplete;
      expect(search.getAttribute("aria-activedescendant")).to.equal("notification-group-mute-option-0");
      search.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key: "Enter" }));
      await waitForMicrotask();
      await element.updateComplete;

      // Verify the mute request, success feedback, refresh trigger, cache invalidation, and focus restoration.
      expect(fetchMock.calls.map(([url]) => url)).to.deep.equal([
        "/dashboard/user/notifications/group-options",
        "/dashboard/user/notifications/muted-groups/group-1",
      ]);
      expect(env.current.htmx.triggerCalls).to.deep.equal([[document.body, "refresh-muted-groups"]]);
      expect(env.current.swal.calls[0]).to.include({ text: "Kubernetes Group muted.", icon: "success" });
      expect(element._loadStatus).to.equal("idle");
      expect(element._options).to.deep.equal([]);
      expect(search.value).to.equal("");
      expect(document.activeElement).to.equal(search);
    } finally {
      fetchMock.restore();
    }
  });

  it("blocks duplicate activation while a mute request is busy", async () => {
    let resolvePut;
    const pendingPut = new Promise((resolve) => {
      resolvePut = resolve;
    });
    const fetchMock = mockFetch({
      impl: (_url, init = {}) => (init.method === "PUT" ? pendingPut : optionsResponse()),
    });

    try {
      // Render and load the options.
      const element = await mountGroupMutes();
      await loadOptions(element);

      // Activate the same option twice before the PUT resolves.
      const option = element.querySelector('[role="option"]');
      option.click();
      option.click();
      await waitForMicrotask();
      expect(fetchMock.calls.filter(([, init = {}]) => init.method === "PUT")).to.have.length(1);

      // Resolve the pending request to let the component settle.
      resolvePut(new Response(null, { status: 204 }));
      await waitForMicrotask();
      await element.updateComplete;
    } finally {
      fetchMock.restore();
    }
  });

  it("shows the server message, reloads options, and keeps focus after an OCG01 failure", async () => {
    const fetchMock = mockFetch({
      impl: (_url, init = {}) =>
        init.method === "PUT"
          ? new Response("group not available to mute", { status: 422 })
          : optionsResponse(),
    });

    try {
      // Render, load options, and fail the mute request.
      const element = await mountGroupMutes();
      await loadOptions(element);
      element.querySelector('[role="option"]').click();
      await waitForMicrotask();
      await element.updateComplete;

      // Verify the server message is shown, options are reloaded, and focus returns to the input.
      expect(env.current.swal.calls[0].html).to.include("group not available to mute");
      expect(fetchMock.calls.filter(([, init = {}]) => init.method !== "PUT")).to.have.length(2);
      expect(element.querySelectorAll('[role="option"]')).to.have.length(2);
      expect(document.activeElement).to.equal(element.querySelector("#notification-group-mute-search"));
    } finally {
      fetchMock.restore();
    }
  });

  it("returns focus to the search after the mute success alert closes", async () => {
    const fetchMock = mockFetch({
      impl: (_url, init = {}) => (init.method === "PUT" ? new Response(null, { status: 204 }) : optionsResponse()),
    });
    const alert = emulateSwalFocusReturn();

    try {
      // Render, load options, and select an option with the mouse, which focuses it.
      const element = await mountGroupMutes();
      const search = await loadOptions(element);
      const option = element.querySelector('[role="option"]');
      option.focus();
      option.click();
      await waitForMicrotask();
      await element.updateComplete;

      // Close the alert after the refreshed picker removed the selected option.
      expect(env.current.swal.calls[0]).to.include({ text: "Kubernetes Group muted.", icon: "success" });
      expect(option.isConnected).to.equal(false);
      alert.close();
      await waitForMicrotask();
      await element.updateComplete;

      // Focus returns to the stable search input instead of body.
      expect(document.activeElement.id).to.equal(search.id);
    } finally {
      fetchMock.restore();
    }
  });

  it("returns focus to the search after the mute error alert closes", async () => {
    const fetchMock = mockFetch({
      impl: (_url, init = {}) =>
        init.method === "PUT"
          ? new Response("group not available to mute", { status: 422 })
          : new Response(JSON.stringify(GROUPS.slice(1)), { status: 200 }),
    });
    const alert = emulateSwalFocusReturn();

    try {
      // Render, load options, and fail a mouse-selected mute.
      const element = await mountGroupMutes();
      const search = await loadOptions(element);
      const option = element.querySelector('[role="option"]');
      option.focus();
      option.click();
      await waitForMicrotask();
      await element.updateComplete;

      // Close the alert after the reloaded options removed the selected option.
      expect(env.current.swal.calls[0].html).to.include("group not available to mute");
      expect(option.isConnected).to.equal(false);
      alert.close();
      await waitForMicrotask();
      await element.updateComplete;

      // Focus returns to the stable search input instead of body.
      expect(document.activeElement.id).to.equal(search.id);
    } finally {
      fetchMock.restore();
    }
  });

  it("offers retry after a failed load", async () => {
    let shouldFail = true;
    const fetchMock = mockFetch({
      impl: () => (shouldFail ? new Response("Nope", { status: 500 }) : optionsResponse()),
    });

    try {
      // Render and fail the initial options load.
      const element = await mountGroupMutes();
      await loadOptions(element);

      // Retry from the error state.
      const alert = element.querySelector('[role="alert"]');
      expect(alert.textContent).to.include("Groups could not be loaded");
      shouldFail = false;
      alert.querySelector("button").click();
      await waitForMicrotask();
      await element.updateComplete;

      // Verify retry loaded the options.
      expect(fetchMock.calls).to.have.length(2);
      expect(element.querySelectorAll('[role="option"]')).to.have.length(2);
      expect(document.activeElement).to.equal(element.querySelector("#notification-group-mute-search"));
    } finally {
      fetchMock.restore();
    }
  });

  it("reopening after a failed load retries options", async () => {
    let shouldFail = true;
    const fetchMock = mockFetch({
      impl: () => (shouldFail ? new Response("Nope", { status: 500 }) : optionsResponse()),
    });

    try {
      // Render and fail the initial load.
      const element = await mountGroupMutes();
      const search = await loadOptions(element);
      search.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "Escape" }));
      await element.updateComplete;

      // Reopen the dropdown after making the endpoint succeed.
      shouldFail = false;
      search.click();
      await waitForMicrotask();
      await element.updateComplete;

      // Verify reopening retried and rendered options.
      expect(fetchMock.calls).to.have.length(2);
      expect(element.querySelectorAll('[role="option"]')).to.have.length(2);
    } finally {
      fetchMock.restore();
    }
  });

  it("invalidates cached options on external refresh events", async () => {
    const fetchMock = mockFetch({ impl: () => optionsResponse() });

    try {
      // Render and load the options.
      const element = await mountGroupMutes();
      await loadOptions(element);
      expect(element._loadStatus).to.equal("ready");

      // Dispatch the refresh event fired by HTMX unmute actions.
      document.body.dispatchEvent(new Event("refresh-muted-groups"));

      // Verify the cached options were dropped.
      expect(element._loadStatus).to.equal("idle");
      expect(element._options).to.deep.equal([]);
    } finally {
      fetchMock.restore();
    }
  });

  it("renders loading and empty states", async () => {
    let resolveOptions;
    const pendingOptions = new Promise((resolve) => {
      resolveOptions = resolve;
    });
    const fetchMock = mockFetch({ impl: () => pendingOptions });

    try {
      // Start loading options and inspect the pending state.
      const element = await mountGroupMutes();
      const search = element.querySelector("#notification-group-mute-search");
      search.focus();
      await element.updateComplete;
      expect(search.placeholder).to.equal("Loading groups...");
      expect(element.querySelector('[role="status"]').textContent.trim()).to.equal("Loading groups to mute...");
      expect(element.textContent).to.include("Loading groups...");

      // Resolve with no options and inspect the empty state.
      resolveOptions(new Response("[]", { status: 200 }));
      await waitForMicrotask();
      await element.updateComplete;
      expect(element.textContent).to.include("No groups available to mute.");
    } finally {
      fetchMock.restore();
    }
  });

  it("prevents Enter from submitting a form when no option is selected", async () => {
    const fetchMock = mockFetch({ impl: () => optionsResponse() });

    try {
      // Render the component in a form and load options.
      document.body.innerHTML = `
        <form>
          <notification-group-mutes options-url="/dashboard/user/notifications/group-options"></notification-group-mutes>
        </form>
      `;
      const element = document.querySelector("notification-group-mutes");
      await element.updateComplete;
      const search = await loadOptions(element);

      // Search to an empty result set and press Enter.
      search.value = "missing";
      search.dispatchEvent(new Event("input", { bubbles: true }));
      await element.updateComplete;
      const event = new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key: "Enter" });
      search.dispatchEvent(event);

      // The Enter key is consumed instead of submitting the form.
      expect(event.defaultPrevented).to.equal(true);
    } finally {
      fetchMock.restore();
    }
  });

  it("moves focus to the muted groups heading when an HTMX swap removes the active element", async () => {
    // Render the stable heading and muted-groups wrapper used by the template.
    document.body.innerHTML = `
      <h2 id="muted-groups-title" tabindex="-1">Muted groups</h2>
      <div id="muted-groups"><button type="button">Unmute Kubernetes Group</button></div>
    `;
    const wrapper = document.getElementById("muted-groups");
    const button = wrapper.querySelector("button");
    button.focus();
    button.remove();

    // Dispatch the HTMX event fired after the wrapper innerHTML is replaced.
    dispatchHtmxAfterSwap(wrapper, { target: wrapper });

    // Focus lands on the stable section heading instead of body.
    expect(document.activeElement).to.equal(document.getElementById("muted-groups-title"));
  });

  it("returns focus to the muted groups heading after the Unmute success alert closes", async () => {
    // Register the shared handlers that open the declarative success alert.
    registerHtmxResponseHandlers(document);

    const alert = emulateSwalFocusReturn();

    // Render the stable heading and an Unmute button configured like the partial.
    document.body.innerHTML = `
      <h2 id="muted-groups-title" tabindex="-1">Muted groups</h2>
      <div id="muted-groups">
        <button type="button" data-htmx-response data-success-message="Kubernetes Group unmuted.">
          Unmute Kubernetes Group
        </button>
      </div>
    `;
    const wrapper = document.getElementById("muted-groups");
    wrapper.querySelector("button").focus();

    // Resolve the Unmute request, then swap in the refreshed list while the alert is open.
    dispatchHtmxBeforeOnLoad(wrapper.querySelector("button"), { status: 204 });
    wrapper.innerHTML = "<p>You haven't muted any groups.</p>";
    dispatchHtmxAfterSwap(wrapper, { target: wrapper });

    // Closing the alert returns focus to the heading instead of the removed button.
    expect(env.current.swal.calls).to.have.length(1);
    alert.close();
    expect(document.activeElement).to.equal(document.getElementById("muted-groups-title"));
  });

  it("keeps focus on the Unmute button when the request fails", async () => {
    // Render the stable heading and a focused Unmute button.
    document.body.innerHTML = `
      <h2 id="muted-groups-title" tabindex="-1">Muted groups</h2>
      <div id="muted-groups"><button type="button">Unmute Kubernetes Group</button></div>
    `;
    const button = document.querySelector("#muted-groups button");
    button.focus();

    // Resolve the Unmute request with a user-facing rejection.
    dispatchHtmxBeforeOnLoad(button, { status: 422 });

    // Focus stays on the button, which remains in the list.
    expect(document.activeElement).to.equal(button);
  });

  it("keeps focus unchanged when the muted groups list refresh loads", async () => {
    // Render the stable heading, the list wrapper, and a focused search input.
    document.body.innerHTML = `
      <h2 id="muted-groups-title" tabindex="-1">Muted groups</h2>
      <input id="notification-group-mute-search" />
      <div id="muted-groups"></div>
    `;
    const search = document.getElementById("notification-group-mute-search");
    search.focus();

    // Resolve the list refresh request issued by the wrapper itself.
    dispatchHtmxBeforeOnLoad(document.getElementById("muted-groups"), { status: 200 });

    // Focus stays on the search input after a mute.
    expect(document.activeElement).to.equal(search);
  });
});
