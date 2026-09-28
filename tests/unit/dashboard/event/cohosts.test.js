import { expect } from "@open-wc/testing";

import "/static/js/dashboard/event/cohosts.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

// Inline logo used by fixtures to avoid image requests.
const LOGO_URL = "data:image/gif;base64,R0lGODlhAQABAAAAACw=";

// Communities offered by the selector fixture.
const COMMUNITIES = [
  {
    community_id: "community-1",
    display_name: "Community One",
    name: "community-one",
  },
  {
    community_id: "community-2",
    display_name: "Community Two",
    name: "community-two",
  },
];

// Group options returned by the mocked lookup endpoint.
const GROUPS = [
  {
    community_display_name: "Community One",
    community_name: "community-one",
    group_id: "group-1",
    logo_url: LOGO_URL,
    name: "Group One",
    slug: "group-one",
  },
  {
    community_display_name: "Community One",
    community_name: "community-one",
    group_id: "group-2",
    logo_url: LOGO_URL,
    name: "Group Two",
    slug: "group-two",
  },
];

/**
 * Mounts a co-hosts selector with extra attributes and returns it.
 * @param {string} [attrs=""] - Extra attributes for the selector element.
 * @returns {HTMLElement} Mounted selector.
 */
const mountSelector = (attrs = "") => {
  const selectedCohostsAttr = attrs.includes("selected-cohosts") ? "" : 'selected-cohosts="[]"';
  document.body.innerHTML = `
    <cohosts-selector
      communities='${JSON.stringify(COMMUNITIES)}'
      current-group-id="owner-group"
      revision="7"
      ${selectedCohostsAttr}
      ${attrs}
    ></cohosts-selector>
  `;
  return document.querySelector("cohosts-selector");
};

/**
 * Focuses the group search to trigger the first groups load and waits for the render.
 * @param {HTMLElement} element - Mounted selector.
 * @returns {Promise<void>}
 */
const loadGroups = async (element) => {
  element.querySelector("#cohost-group-search").dispatchEvent(new Event("focus"));
  await waitForMicrotask();
  await element.updateComplete;
};

describe("event co-hosts selector", () => {
  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    resetDom();
  });

  it("loads group options when the community changes", async () => {
    const fetchMock = mockFetch({
      response: new Response(JSON.stringify(GROUPS), { status: 200 }),
    });

    try {
      // Render the selector fixture.
      const element = mountSelector();
      await element.updateComplete;

      // Switch to the second community.
      element.querySelector("#cohost-community").value = "community-2";
      element.querySelector("#cohost-community").dispatchEvent(new Event("change", { bubbles: true }));
      await waitForMicrotask();

      // Verify the groups lookup targets the selected community.
      expect(fetchMock.calls).to.have.length(1);
      expect(fetchMock.calls[0][0]).to.equal(
        "/dashboard/group/events/cohosts/groups?community_id=community-2",
      );
    } finally {
      fetchMock.restore();
    }
  });

  it("keeps the latest groups after rapid community switches", async () => {
    // Hold the first community response until the second one settles.
    let resolveFirst;
    const first = new Promise((resolve) => {
      resolveFirst = resolve;
    });
    const secondGroups = [{ ...GROUPS[1], name: "Latest Group" }];
    const fetchMock = mockFetch({
      impl: (url) => {
        if (String(url).includes("community_id=community-1")) {
          return first;
        }
        return new Response(JSON.stringify(secondGroups), { status: 200 });
      },
    });

    try {
      // Render the selector fixture.
      const element = mountSelector();
      await element.updateComplete;

      // Start loading the first community, then switch to the second one.
      element.querySelector("#cohost-group-search").dispatchEvent(new Event("focus"));
      await waitForMicrotask();
      element.querySelector("#cohost-community").value = "community-2";
      element.querySelector("#cohost-community").dispatchEvent(new Event("change", { bubbles: true }));
      await waitForMicrotask();

      // Resolve the stale first response last.
      resolveFirst(new Response(JSON.stringify(GROUPS), { status: 200 }));
      await waitForMicrotask();
      await element.updateComplete;

      // Verify the stale response did not overwrite the latest groups.
      expect(element._groups).to.deep.equal(secondGroups);
    } finally {
      fetchMock.restore();
    }
  });

  it("aborts an in-flight lookup when disconnected", async () => {
    // Capture the lookup signal and keep the request pending.
    let signal;
    const fetchMock = mockFetch({
      impl: (_url, init) => {
        signal = init.signal;
        return new Promise(() => {});
      },
    });

    try {
      // Render the selector and start a groups lookup.
      const element = mountSelector();
      await element.updateComplete;
      element.querySelector("#cohost-group-search").dispatchEvent(new Event("focus"));
      await waitForMicrotask();

      // Disconnect the selector while the lookup is pending.
      element.remove();

      // Verify the pending lookup was aborted.
      expect(signal.aborted).to.equal(true);
    } finally {
      fetchMock.restore();
    }
  });

  it("keeps the selection and offers a retry when loading groups fails", async () => {
    const selected = [
      {
        community_display_name: "Community One",
        group_active: true,
        group_id: "group-1",
        logo_url: LOGO_URL,
        name: "Group One",
        status: "approved",
      },
    ];
    const fetchMock = mockFetch({
      response: new Response("Nope", { status: 500 }),
    });

    try {
      // Render a loaded selection and fail the groups lookup.
      const element = mountSelector(`selected-cohosts='${JSON.stringify(selected)}'`);
      await element.updateComplete;
      await loadGroups(element);

      // Verify the selection is kept and a retry is offered.
      expect(element.selectedCohosts[0].name).to.equal("Group One");
      expect(element.textContent).to.include("try again");
      expect(element.querySelector("button").textContent).to.include("Retry");
    } finally {
      fetchMock.restore();
    }
  });

  it("keeps the search focused while groups load and opens the options when ready", async () => {
    // Hold the groups response to inspect the loading state.
    let resolveGroups;
    const pending = new Promise((resolve) => {
      resolveGroups = resolve;
    });
    const fetchMock = mockFetch({ impl: () => pending });

    try {
      // Focus the search to start the first groups load.
      const element = mountSelector();
      await element.updateComplete;
      const search = element.querySelector("#cohost-group-search");
      search.focus();
      await element.updateComplete;

      // Verify the loading copy stays inside the search and its dropdown without shifting the page.
      const status = element.querySelector('[role="status"]');
      expect(status.classList.contains("sr-only")).to.equal(true);
      expect(status.textContent.trim()).to.equal("Loading co-host groups...");
      expect(search.placeholder).to.equal("Loading groups...");

      // Verify the search stays enabled and focused while loading.
      expect(search.disabled).to.equal(false);
      expect(document.activeElement).to.equal(search);

      // Resolve the lookup and wait for the render.
      resolveGroups(new Response(JSON.stringify(GROUPS), { status: 200 }));
      await waitForMicrotask();
      await element.updateComplete;

      // Verify the options open for the still focused search and the status clears.
      expect(search.getAttribute("aria-expanded")).to.equal("true");
      expect(element.querySelectorAll('[role="option"]')).to.have.length(2);
      expect(status.textContent.trim()).to.equal("");
    } finally {
      fetchMock.restore();
    }
  });

  it("keeps Enter in the search from submitting the form", async () => {
    const fetchMock = mockFetch({
      response: new Response(JSON.stringify(GROUPS), { status: 200 }),
    });

    /**
     * Dispatches a cancelable Enter keydown on the search and returns it.
     * @param {HTMLInputElement} search - Group search input.
     * @returns {KeyboardEvent} Dispatched event.
     */
    const pressEnter = (search) => {
      const event = new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key: "Enter" });
      search.dispatchEvent(event);
      return event;
    };

    try {
      // Render the selector and load its groups.
      const element = mountSelector();
      await element.updateComplete;
      const search = element.querySelector("#cohost-group-search");
      await loadGroups(element);

      // Verify Enter is blocked when the query matches no groups.
      search.value = "missing";
      search.dispatchEvent(new Event("input", { bubbles: true }));
      await element.updateComplete;
      expect(pressEnter(search).defaultPrevented).to.equal(true);

      // Verify Enter is blocked when the options are closed.
      search.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "Escape" }));
      await element.updateComplete;
      expect(search.getAttribute("aria-expanded")).to.equal("false");
      expect(pressEnter(search).defaultPrevented).to.equal(true);

      // Verify Enter still selects the highlighted option.
      search.value = "";
      search.dispatchEvent(new Event("input", { bubbles: true }));
      search.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "ArrowDown" }));
      await element.updateComplete;
      expect(pressEnter(search).defaultPrevented).to.equal(true);
      await element.updateComplete;
      expect(element.selectedCohosts.map((cohost) => cohost.group_id)).to.deep.equal(["group-1"]);
    } finally {
      fetchMock.restore();
    }
  });

  it("announces load errors and keeps focus on the search when retrying", async () => {
    // Fail the first lookup and succeed on retry.
    let fail = true;
    const fetchMock = mockFetch({
      impl: () =>
        fail ? new Response("Nope", { status: 500 }) : new Response(JSON.stringify(GROUPS), { status: 200 }),
    });

    try {
      // Render the selector and fail the first groups load.
      const element = mountSelector();
      await element.updateComplete;
      await loadGroups(element);

      // Verify the error is announced with a retry action.
      const alert = element.querySelector('[role="alert"]');
      expect(alert?.textContent).to.include("could not be loaded");
      const retry = alert.querySelector("button");
      retry.focus();

      // Retry the lookup.
      fail = false;
      retry.click();
      await element.updateComplete;

      // Verify focus moved to the search before the retry button was removed.
      const search = element.querySelector("#cohost-group-search");
      expect(document.activeElement).to.equal(search);
      expect(element.querySelector('[role="alert"]')).to.equal(null);

      // Verify the reloaded options open for the focused search.
      await waitForMicrotask();
      await element.updateComplete;
      expect(fetchMock.calls).to.have.length(2);
      expect(search.getAttribute("aria-expanded")).to.equal("true");
      expect(element.querySelectorAll('[role="option"]')).to.have.length(2);
    } finally {
      fetchMock.restore();
    }
  });

  it("adds, removes, and submits co-host fields only after changes", async () => {
    const fetchMock = mockFetch({
      response: new Response(JSON.stringify(GROUPS), { status: 200 }),
    });

    try {
      // Render the selector and verify no co-host fields are submitted yet.
      const element = mountSelector();
      await element.updateComplete;
      expect(element.querySelector('input[name="cohost_group_ids_present"]')).to.equal(null);

      // Add the first group option.
      await loadGroups(element);
      element.querySelector('[role="option"]').click();
      await element.updateComplete;

      // Verify the selection and its submitted fields.
      expect(element.selectedCohosts.map((cohost) => cohost.group_id)).to.deep.equal(["group-1"]);
      expect(element.querySelector('input[name="cohost_group_ids[0]"]')?.value).to.equal("group-1");
      expect(element.querySelector('input[name="cohost_group_ids_present"]').value).to.equal("true");
      expect(element.querySelector('input[name="cohosts_revision"]').value).to.equal("7");

      // Remove the added group.
      element.querySelector('[aria-label="Remove Group One"]').click();
      await element.updateComplete;

      // Verify the unchanged selection submits no co-host fields.
      expect(element.selectedCohosts).to.deep.equal([]);
      expect(element.querySelector('input[name="cohost_group_ids[0]"]')).to.equal(null);
      expect(element.querySelector('input[name="cohost_group_ids_present"]')).to.equal(null);
    } finally {
      fetchMock.restore();
    }
  });

  it("exposes the group search as an ARIA combobox tied to its options", async () => {
    const fetchMock = mockFetch({
      response: new Response(JSON.stringify(GROUPS), { status: 200 }),
    });

    try {
      // Render the selector before any options exist.
      const element = mountSelector();
      await element.updateComplete;
      const search = element.querySelector("#cohost-group-search");

      // Verify the combobox semantics and that it points at no missing listbox.
      expect(search.getAttribute("role")).to.equal("combobox");
      expect(search.getAttribute("aria-autocomplete")).to.equal("list");
      expect(search.getAttribute("aria-haspopup")).to.equal("listbox");
      expect(search.hasAttribute("aria-controls")).to.equal(false);
      expect(search.hasAttribute("aria-activedescendant")).to.equal(false);

      // Load the options and verify they are referenced and kept out of the tab order.
      await loadGroups(element);
      const listbox = element.querySelector('[role="listbox"]');
      expect(search.getAttribute("aria-controls")).to.equal(listbox.id);
      const options = [...element.querySelectorAll('[role="option"]')];
      expect(options.map((option) => option.id)).to.deep.equal([
        "cohost-group-option-0",
        "cohost-group-option-1",
      ]);
      expect(options.map((option) => option.getAttribute("tabindex"))).to.deep.equal(["-1", "-1"]);
      expect(options.map((option) => option.getAttribute("aria-selected"))).to.deep.equal(["false", "false"]);

      // Move the active option and verify it is announced and scrolled into view.
      let scrolledOptionId = "";
      options[1].scrollIntoView = () => {
        scrolledOptionId = options[1].id;
      };
      search.dispatchEvent(new Event("input", { bubbles: true }));
      search.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "ArrowDown" }));
      search.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "ArrowDown" }));
      await element.updateComplete;
      await waitForMicrotask();
      expect(search.getAttribute("aria-activedescendant")).to.equal("cohost-group-option-1");
      expect(options[1].getAttribute("aria-selected")).to.equal("true");
      expect(scrolledOptionId).to.equal("cohost-group-option-1");

      // Close the options and verify the active descendant is cleared.
      search.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "Escape" }));
      await element.updateComplete;
      expect(search.hasAttribute("aria-activedescendant")).to.equal(false);
    } finally {
      fetchMock.restore();
    }
  });

  it("renders group logos as decorative images", async () => {
    const fetchMock = mockFetch({
      response: new Response(JSON.stringify(GROUPS), { status: 200 }),
    });

    try {
      // Render one selected co-host and the group options.
      const selected = [{ ...GROUPS[0], status: "approved" }];
      const element = mountSelector(`selected-cohosts='${JSON.stringify(selected)}'`);
      await element.updateComplete;
      await loadGroups(element);

      // Verify logos do not repeat the group names already rendered as text.
      const images = [...element.querySelectorAll("img")];
      expect(images).to.have.length(2);
      expect(images.map((image) => image.getAttribute("alt"))).to.deep.equal(["", ""]);
    } finally {
      fetchMock.restore();
    }
  });

  it("returns focus to the closed search after choosing an option", async () => {
    const fetchMock = mockFetch({
      response: new Response(JSON.stringify(GROUPS), { status: 200 }),
    });

    try {
      // Render the selector and choose an option with the pointer.
      const element = mountSelector();
      await element.updateComplete;
      await loadGroups(element);
      const option = element.querySelector('[role="option"]');
      option.focus();
      option.click();
      await element.updateComplete;
      await waitForMicrotask();

      // Verify focus returned to the search without reopening the options.
      const search = element.querySelector("#cohost-group-search");
      expect(document.activeElement).to.equal(search);
      expect(search.getAttribute("aria-expanded")).to.equal("false");
    } finally {
      fetchMock.restore();
    }
  });

  it("keeps focus near removed co-hosts", async () => {
    const selected = [
      { ...GROUPS[0], status: "approved" },
      { ...GROUPS[1], status: "pending" },
    ];

    // Remove the first of two selected co-hosts.
    const element = mountSelector(`selected-cohosts='${JSON.stringify(selected)}'`);
    await element.updateComplete;
    element.querySelector('[aria-label="Remove Group One"]').click();
    await element.updateComplete;
    await waitForMicrotask();

    // Verify focus moved to the next remove button.
    expect(document.activeElement).to.equal(element.querySelector('[aria-label="Remove Group Two"]'));

    // Remove the last co-host and verify focus moved to the closed search.
    document.activeElement.click();
    await element.updateComplete;
    await waitForMicrotask();
    const search = element.querySelector("#cohost-group-search");
    expect(document.activeElement).to.equal(search);
    expect(search.getAttribute("aria-expanded")).to.equal("false");
  });

  it("submits the present marker when clearing loaded co-hosts", async () => {
    const selected = [
      {
        community_display_name: "Community One",
        group_id: "group-1",
        logo_url: LOGO_URL,
        name: "Group One",
        status: "pending",
      },
    ];

    // Render a loaded selection and remove its only co-host.
    const element = mountSelector(`selected-cohosts='${JSON.stringify(selected)}'`);
    await element.updateComplete;

    element.querySelector('[aria-label="Remove Group One"]').click();
    await element.updateComplete;

    // Verify the cleared selection still submits the present marker.
    expect(element.selectedCohosts).to.deep.equal([]);
    expect(element.querySelector('input[name="cohost_group_ids[0]"]')).to.equal(null);
    expect(element.querySelector('input[name="cohost_group_ids_present"]').value).to.equal("true");
  });

  it("does not submit fields or allow interaction while disabled", async () => {
    const element = mountSelector("disabled");
    await element.updateComplete;

    expect(element.querySelector("#cohost-community").disabled).to.equal(true);
    expect(element.querySelector("#cohost-group-search").disabled).to.equal(true);
    expect(element.querySelector('input[name="cohost_group_ids_present"]')).to.equal(null);
  });

  it("returns preview co-hosts with pending and approved statuses", async () => {
    const selected = [
      { group_id: "group-1", logo_url: LOGO_URL, name: "One", status: "approved" },
      { group_id: "group-2", logo_url: LOGO_URL, name: "Two", status: "pending" },
    ];
    const element = mountSelector(`selected-cohosts='${JSON.stringify(selected)}'`);
    await element.updateComplete;

    expect(element.getPreviewCohosts()).to.deep.equal([
      { logo_url: LOGO_URL, name: "One", status: "approved" },
      { logo_url: LOGO_URL, name: "Two", status: "pending" },
    ]);
  });

  it("colors approved co-hosts green and pending co-hosts amber", async () => {
    const selected = [
      { group_id: "group-1", logo_url: LOGO_URL, name: "One", status: "approved" },
      { group_id: "group-2", logo_url: LOGO_URL, name: "Two", status: "pending" },
    ];

    // Render one approved and one pending co-host.
    const element = mountSelector(`selected-cohosts='${JSON.stringify(selected)}'`);
    await element.updateComplete;

    // Verify the status pills use the shared dashboard status colors.
    const [approved, pending] = element.querySelectorAll(".custom-badge");
    expect(approved.textContent.trim()).to.equal("Approved");
    expect([...approved.classList]).to.include.members([
      "border-green-800",
      "bg-green-100",
      "text-green-800",
    ]);
    expect(pending.textContent.trim()).to.equal("Pending");
    expect([...pending.classList]).to.include.members(["border-amber-800", "bg-amber-100", "text-amber-800"]);
  });

  it("shows the community above the group name on selected co-host cards", async () => {
    const selected = [
      {
        community_display_name: "Distributed AI Forum",
        group_id: "group-1",
        logo_url: LOGO_URL,
        name: "Distributed AI Atlanta",
        status: "approved",
      },
    ];

    // Render one selected co-host.
    const element = mountSelector(`selected-cohosts='${JSON.stringify(selected)}'`);
    await element.updateComplete;

    // Verify the community label precedes the group name with the card popover styles.
    const [community, name] = element.querySelector(".rounded-xl .min-w-0.flex-1").children;
    expect(community.textContent.trim()).to.equal("Distributed AI Forum");
    expect([...community.classList]).to.include.members(["uppercase", "text-stone-400", "truncate"]);
    expect(name.textContent.trim()).to.equal("Distributed AI Atlanta");
    expect([...name.classList]).to.include.members(["font-semibold", "text-black", "truncate"]);
  });
});
