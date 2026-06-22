import { expect } from "@open-wc/testing";

import { initializeAllianceGroupsList } from "/static/js/dashboard/alliance/groups-list.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { dispatchHtmxLoad } from "/tests/unit/test-utils/htmx.js";
import { mockFetch, mockPushState } from "/tests/unit/test-utils/network.js";

describe("dashboard alliance groups list page", () => {
  const env = useDashboardTestEnv({
    path: "/dashboard/alliance?tab=groups",
    withHtmx: true,
  });
  let fetchMock;
  let pushStateMock;

  beforeEach(() => {
    fetchMock = mockFetch();
    pushStateMock = mockPushState();
  });

  afterEach(() => {
    fetchMock.restore();
    pushStateMock.restore();
  });

  const renderGroupsList = () => {
    document.body.innerHTML = `
      <form id="groups-search-form">
        <input id="search_groups" name="ts_query" value="cloud">
      </form>
      <table>
        <tbody id="groups-list">
          <tr>
            <td>
              <button type="button" data-select-group-id="group-1">Cloud Native</button>
            </td>
            <td>
              <button class="btn-group-actions" data-group-id="group-1">Actions</button>
              <div id="dropdown-group-actions-group-1" class="dropdown hidden"></div>
            </td>
          </tr>
        </tbody>
      </table>
    `;
  };

  it("submits the search form when enter is pressed", () => {
    // Prepare the groups list controls.
    renderGroupsList();
    initializeAllianceGroupsList();

    // Press enter in the groups search input.
    document.getElementById("search_groups").dispatchEvent(
      new KeyboardEvent("keydown", {
        bubbles: true,
        key: "Enter",
      }),
    );

    // Verify the search form is submitted through HTMX.
    expect(env.current.htmx.triggerCalls).to.deep.equal([
      [document.getElementById("groups-search-form"), "change"],
    ]);
  });

  it("selects a group from the list and prevents duplicate clicks", async () => {
    // Prepare the groups list controls.
    renderGroupsList();
    initializeAllianceGroupsList();

    // Select the group twice before the first request resolves.
    const selectButton = document.querySelector("[data-select-group-id]");
    selectButton.click();
    selectButton.click();
    await waitForMicrotask();

    // Verify the dashboard selection request and body swap were triggered once.
    expect(fetchMock.calls).to.have.length(1);
    expect(fetchMock.calls[0][0]).to.equal("/dashboard/group/group-1/select");
    expect(env.current.htmx.ajaxCalls).to.deep.equal([
      [
        "GET",
        "/dashboard/group",
        {
          target: "body",
          indicator: "#dashboard-spinner",
        },
      ],
    ]);
    expect(pushStateMock.calls).to.deep.equal([[{}, "", "/dashboard/group"]]);
    expect(selectButton.hasAttribute("disabled")).to.equal(false);
  });

  it("toggles group row action menus once", async () => {
    // Prepare the groups list controls.
    renderGroupsList();
    initializeAllianceGroupsList();
    initializeAllianceGroupsList();

    const actionButton = document.querySelector(".btn-group-actions");
    const dropdown = document.getElementById("dropdown-group-actions-group-1");

    // Open the group action menu.
    actionButton.click();
    expect(dropdown.classList.contains("hidden")).to.equal(false);

    // Close the group action menu from an outside click.
    await new Promise((resolve) => setTimeout(resolve, 0));
    document.body.click();
    expect(dropdown.classList.contains("hidden")).to.equal(true);
  });

  it("initializes swapped groups list content on htmx load", () => {
    // Prepare the groups list controls.
    renderGroupsList();

    // Dispatch the lifecycle event used by swapped dashboard content.
    dispatchHtmxLoad(document.body);
    document.querySelector(".btn-group-actions").click();

    // Verify the swapped action menu is initialized.
    expect(
      document
        .getElementById("dropdown-group-actions-group-1")
        .classList.contains("hidden"),
    ).to.equal(false);
  });
});
