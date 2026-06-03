import { expect } from "@open-wc/testing";

import "/static/js/dashboard/group/group-selector.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockHtmx } from "/tests/unit/test-utils/globals.js";

describe("group-selector", () => {
  let htmx;

  beforeEach(() => {
    resetDom();
    htmx = mockHtmx();
  });

  afterEach(() => {
    document
      .querySelectorAll("group-selector")
      .forEach((element) => element.remove());
    resetDom();
    htmx.restore();
  });

  // Render the component fixture.
  const renderSelector = async ({ groups, selectedGroupId = "" }) => {
    const element = document.createElement("group-selector");
    element.groups = groups;
    element.selectedGroupId = selectedGroupId;
    document.body.append(element);
    await element.updateComplete;
    return element;
  };

  it("renders the selected group and its deactivated warning", async () => {
    // Render the selector fixture.
    const element = await renderSelector({
      groups: [
        { group_id: "1", name: "Platform Team", active: false },
        { group_id: "2", name: "Cloud Native", active: true },
      ],
      selectedGroupId: "1",
    });

    // Read the selected group and deactivated warning state.
    const button = element.querySelector("#group-selector-button");
    const warning = element.querySelector(".text-orange-700");

    // Verify renders the selected group and its deactivated warning.
    expect(button?.textContent).to.include("Platform Team");
    expect(warning?.textContent).to.include("This group has been deactivated");
  });

  it("filters groups from the current query", async () => {
    // Render the selector fixture.
    const element = await renderSelector({
      groups: [
        { group_id: "1", name: "Platform Team", active: true },
        { group_id: "2", name: "Cloud Native", active: true },
        { group_id: "3", name: "Design Guild", active: true },
      ],
    });

    // Apply the group search query.
    element._query = "cloud";
    await element.updateComplete;

    // Verify filters groups from the current query.
    expect(element._filteredGroups).to.deep.equal([
      { group_id: "2", name: "Cloud Native", active: true },
    ]);
  });

  it("persists the selected group when an option handler runs", async () => {
    // Render the selector fixture.
    const element = await renderSelector({
      groups: [
        { group_id: "1", name: "Platform Team", active: true },
        { group_id: "2", name: "Cloud Native", active: true },
      ],
      selectedGroupId: "1",
    });

    // Prepare prevented for persisting the selected group when an option handler.
    let prevented = false;
    await element._handleGroupClick(
      {
        preventDefault() {
          prevented = true;
        },
      },
      { group_id: "2", name: "Cloud Native", active: true },
    );
    await element.updateComplete;

    // The selected group persists when an option handler runs.
    expect(htmx.ajaxCalls).to.deep.equal([
      [
        "PUT",
        "/dashboard/group/2/select",
        {
          target: "body",
          indicator: "#dashboard-spinner",
        },
      ],
    ]);
    expect(prevented).to.equal(true);
    expect(element._isSubmitting).to.equal(false);
    expect(element._isOpen).to.equal(false);
  });
});
