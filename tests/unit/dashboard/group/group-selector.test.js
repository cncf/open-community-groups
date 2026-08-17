import { expect } from "@open-wc/testing";

import "/static/js/dashboard/group/group-selector.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockHtmx, mockSwal } from "/tests/unit/test-utils/globals.js";

describe("group-selector", () => {
  let htmx;
  let swal;

  beforeEach(() => {
    resetDom();
    htmx = mockHtmx();
    swal = mockSwal();
  });

  afterEach(() => {
    document.querySelectorAll("group-selector").forEach((element) => element.remove());
    resetDom();
    swal.restore();
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
    const list = element.querySelector("#group-selector-list");
    const option = element.querySelector("#group-option-1");
    const searchInput = element.querySelector("#group-search-input");
    const warning = element.querySelector(".text-orange-700");

    // Verify the default ids and semantic option class remain unchanged.
    expect(button?.textContent).to.include("Platform Team");
    expect(list).to.exist;
    expect(option?.classList.contains("group-button")).to.equal(true);
    expect(searchInput).to.exist;
    expect(warning?.textContent).to.include("This group has been deactivated");
  });

  it("namespaces DOM ids and focuses the prefixed search input", async () => {
    // Render the selector with a mobile id prefix.
    const element = await renderSelector({
      groups: [
        { group_id: "1", name: "Platform Team", active: true },
        { group_id: "2", name: "Cloud Native", active: true },
      ],
      selectedGroupId: "1",
    });
    element.setAttribute("id-prefix", "mobile-group");
    await element.updateComplete;

    // Read the namespaced controls and open the selector.
    const button = element.querySelector("#mobile-group-selector-button");
    const list = element.querySelector("#mobile-group-selector-list");
    const option = element.querySelector("#mobile-group-option-1");
    const searchInput = element.querySelector("#mobile-group-search-input");
    button.click();
    await element.updateComplete;

    // Verify every id is namespaced while the option class and focus behavior remain stable.
    expect(element.querySelector("#group-selector-button")).to.equal(null);
    expect(list).to.exist;
    expect(option?.classList.contains("group-button")).to.equal(true);
    expect(document.activeElement).to.equal(searchInput);
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
    element._combobox.setQuery("cloud");
    await element.updateComplete;

    // Verify filters groups from the current query.
    expect(element._filteredGroups).to.deep.equal([{ group_id: "2", name: "Cloud Native", active: true }]);
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
    expect(element._combobox.isOpen).to.equal(false);
  });

  it("shows an error and keeps the selector usable when selection fails", async () => {
    // Replace the HTMX mock with a failing selection request.
    htmx.restore();
    htmx = mockHtmx({
      ajaxImpl: async () => {
        throw new Error("Selection failed");
      },
    });

    // Render the selector fixture.
    const element = await renderSelector({
      groups: [
        { group_id: "1", name: "Platform Team", active: true },
        { group_id: "2", name: "Cloud Native", active: true },
      ],
      selectedGroupId: "1",
    });

    // Select a different group from the selector.
    await element._handleGroupClick(
      {
        preventDefault() {},
      },
      { group_id: "2", name: "Cloud Native", active: true },
    );
    await element.updateComplete;

    // The failed selection leaves the selector usable and reports the error.
    expect(element._isSubmitting).to.equal(false);
    expect(element._combobox.isOpen).to.equal(false);
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0]).to.include({
      text: "Something went wrong selecting the group. Please try again later.",
      icon: "error",
    });
  });
});
