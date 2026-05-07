import { expect } from "@open-wc/testing";

import "/static/js/dashboard/group/sponsors.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { dispatchHtmxLoad } from "/tests/unit/test-utils/htmx.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

describe("dashboard group sponsors", () => {
  useDashboardTestEnv({
    path: "/dashboard/group/sponsors",
    withScroll: true,
    withSwal: true,
  });

  let fetchMock;

  beforeEach(() => {
    fetchMock = mockFetch();
  });

  afterEach(() => {
    fetchMock.restore();
  });

  it("updates sponsor featured toggles after the dashboard body is swapped", async () => {
    const replacementBody = document.createElement("body");
    replacementBody.innerHTML = `
      <label class="cursor-pointer">
        <input
          type="checkbox"
          class="sponsor-featured-toggle"
          data-url="/dashboard/group/sponsors/sponsor-7/featured"
        />
      </label>
      <div id="dashboard-content"></div>
    `;
    document.documentElement.replaceChild(replacementBody, document.body);

    dispatchHtmxLoad();
    const checkbox = document.querySelector(".sponsor-featured-toggle");
    checkbox.checked = true;
    checkbox.dispatchEvent(new Event("change", { bubbles: true }));

    await waitForMicrotask();

    expect(fetchMock.calls).to.have.length(1);
    expect(fetchMock.calls[0][0]).to.equal("/dashboard/group/sponsors/sponsor-7/featured");
    expect(checkbox.dataset.currentChecked).to.equal("true");
  });
});
