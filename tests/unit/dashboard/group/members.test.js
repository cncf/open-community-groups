import { expect } from "@open-wc/testing";

import "/static/js/dashboard/group/members.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import {
  dispatchHtmxAfterRequest,
  dispatchHtmxLoad,
} from "/tests/unit/test-utils/htmx.js";

describe("dashboard group members", () => {
  const env = useDashboardTestEnv({
    path: "/dashboard/group/members",
    withScroll: true,
    withSwal: true,
  });

  it("initializes the members notification modal with the members success copy", async () => {
    // Build the DOM fixture to check it initializes the members notification modal.
    document.body.innerHTML = `
      <button id="open-notification-modal" type="button">Open</button>
      <div id="notification-modal" class="hidden"></div>
      <button id="close-notification-modal" type="button">Close</button>
      <button id="cancel-notification" type="button">Cancel</button>
      <div id="overlay-notification-modal"></div>
      <form id="notification-form">
        <input name="message" value="hello" />
      </form>
    `;

    // Dispatch the HTMX load event to check it initializes the members notification.
    dispatchHtmxLoad();

    // Dispatch the HTMX after request event to check it initializes the members.
    dispatchHtmxAfterRequest(document.getElementById("notification-form"), {
      status: 204,
    });

    // Confirm it initializes the members notification modal with the members success.
    expect(env.current.swal.calls[0]).to.include({
      text: "Email sent successfully to all group members.",
      icon: "success",
    });
  });

  it("opens the notification modal after the dashboard body is swapped", () => {
    // Prepare replacement body to check it opens the notification modal.
    const replacementBody = document.createElement("body");
    replacementBody.innerHTML = `
      <button id="open-notification-modal" type="button">Open</button>
      <div id="notification-modal" class="hidden"></div>
      <button id="close-notification-modal" type="button">Close</button>
      <button id="cancel-notification" type="button">Cancel</button>
      <div id="overlay-notification-modal"></div>
      <form id="notification-form"></form>
    `;

    // Exercise the flow to check it opens the notification modal after the dashboard.
    document.documentElement.replaceChild(replacementBody, document.body);

    // Dispatch the HTMX load event to check it opens the notification modal.
    dispatchHtmxLoad();
    document.getElementById("open-notification-modal")?.click();

    // Confirm it opens the notification modal after the dashboard body is swapped.
    expect(
      document
        .getElementById("notification-modal")
        ?.classList.contains("hidden"),
    ).to.equal(false);
  });
});
