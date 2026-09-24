import { expect } from "@open-wc/testing";

import "/static/js/dashboard/event/cohosts.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

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

const GROUPS = [
  {
    community_display_name: "Community One",
    community_name: "community-one",
    group_id: "group-1",
    logo_url: "/group-one.svg",
    name: "Group One",
    slug: "group-one",
  },
  {
    community_display_name: "Community One",
    community_name: "community-one",
    group_id: "group-2",
    logo_url: "/group-two.svg",
    name: "Group Two",
    slug: "group-two",
  },
];

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
      const element = mountSelector();
      await element.updateComplete;

      element.querySelector("#cohost-community").value = "community-2";
      element
        .querySelector("#cohost-community")
        .dispatchEvent(new Event("change", { bubbles: true }));
      await waitForMicrotask();

      expect(fetchMock.calls).to.have.length(1);
      expect(fetchMock.calls[0][0]).to.equal(
        "/dashboard/group/events/cohosts/groups?community_id=community-2",
      );
    } finally {
      fetchMock.restore();
    }
  });

  it("keeps the latest groups after rapid community switches", async () => {
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
      const element = mountSelector();
      await element.updateComplete;

      element.querySelector("#cohost-group-search").dispatchEvent(new Event("focus"));
      await waitForMicrotask();
      element.querySelector("#cohost-community").value = "community-2";
      element
        .querySelector("#cohost-community")
        .dispatchEvent(new Event("change", { bubbles: true }));
      await waitForMicrotask();
      resolveFirst(new Response(JSON.stringify(GROUPS), { status: 200 }));
      await waitForMicrotask();
      await element.updateComplete;

      expect(element._groups).to.deep.equal(secondGroups);
    } finally {
      fetchMock.restore();
    }
  });

  it("aborts an in-flight lookup when disconnected", async () => {
    let signal;
    const fetchMock = mockFetch({
      impl: (_url, init) => {
        signal = init.signal;
        return new Promise(() => {});
      },
    });

    try {
      const element = mountSelector();
      await element.updateComplete;
      element.querySelector("#cohost-group-search").dispatchEvent(new Event("focus"));
      await waitForMicrotask();

      element.remove();

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
        logo_url: "/group-one.svg",
        name: "Group One",
        status: "approved",
      },
    ];
    const fetchMock = mockFetch({
      response: new Response("Nope", { status: 500 }),
    });

    try {
      const element = mountSelector(`selected-cohosts='${JSON.stringify(selected)}'`);
      await element.updateComplete;
      await loadGroups(element);

      expect(element.selectedCohosts[0].name).to.equal("Group One");
      expect(element.textContent).to.include("try again");
      expect(element.querySelector("button").textContent).to.include("Retry");
    } finally {
      fetchMock.restore();
    }
  });

  it("adds, removes, and submits co-host fields only after changes", async () => {
    const fetchMock = mockFetch({
      response: new Response(JSON.stringify(GROUPS), { status: 200 }),
    });

    try {
      const element = mountSelector();
      await element.updateComplete;
      expect(element.querySelector('input[name="cohost_group_ids_present"]')).to.equal(null);

      await loadGroups(element);
      element.querySelector('[role="option"]').click();
      await element.updateComplete;

      expect(element.selectedCohosts.map((cohost) => cohost.group_id)).to.deep.equal(["group-1"]);
      expect(element.querySelector('input[name="cohost_group_ids[0]"]')?.value).to.equal("group-1");
      expect(element.querySelector('input[name="cohost_group_ids_present"]').value).to.equal("true");
      expect(element.querySelector('input[name="cohosts_revision"]').value).to.equal("7");

      element.querySelector('[aria-label="Remove Group One"]').click();
      await element.updateComplete;

      expect(element.selectedCohosts).to.deep.equal([]);
      expect(element.querySelector('input[name="cohost_group_ids[0]"]')).to.equal(null);
      expect(element.querySelector('input[name="cohost_group_ids_present"]')).to.equal(null);
    } finally {
      fetchMock.restore();
    }
  });

  it("submits the present marker when clearing loaded co-hosts", async () => {
    const selected = [
      {
        community_display_name: "Community One",
        group_id: "group-1",
        logo_url: "/group-one.svg",
        name: "Group One",
        status: "pending",
      },
    ];
    const element = mountSelector(`selected-cohosts='${JSON.stringify(selected)}'`);
    await element.updateComplete;

    element.querySelector('[aria-label="Remove Group One"]').click();
    await element.updateComplete;

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
      { group_id: "group-1", logo_url: "/one.svg", name: "One", status: "approved" },
      { group_id: "group-2", logo_url: "/two.svg", name: "Two", status: "pending" },
    ];
    const element = mountSelector(`selected-cohosts='${JSON.stringify(selected)}'`);
    await element.updateComplete;

    expect(element.getPreviewCohosts()).to.deep.equal([
      { logo_url: "/one.svg", name: "One", status: "approved" },
      { logo_url: "/two.svg", name: "Two", status: "pending" },
    ]);
  });
});
