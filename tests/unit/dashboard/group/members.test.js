import { expect } from "@open-wc/testing";

import "/static/js/dashboard/group/members.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { dispatchHtmxAfterRequest, dispatchHtmxLoad } from "/tests/unit/test-utils/htmx.js";

describe("dashboard group members", () => {
  const env = useDashboardTestEnv({
    path: "/dashboard/group/members",
    withScroll: true,
    withSwal: true,
  });

  it("initializes the members notification modal with the members success copy", async () => {
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

    dispatchHtmxLoad();

    dispatchHtmxAfterRequest(document.getElementById("notification-form"), {
      status: 204,
    });

    expect(env.current.swal.calls[0]).to.include({
      text: "Email sent successfully to all group members.",
      icon: "success",
    });
  });

  it("opens the notification modal after the dashboard body is swapped", () => {
    const replacementBody = document.createElement("body");
    replacementBody.innerHTML = `
      <button id="open-notification-modal" type="button">Open</button>
      <div id="notification-modal" class="hidden"></div>
      <button id="close-notification-modal" type="button">Close</button>
      <button id="cancel-notification" type="button">Cancel</button>
      <div id="overlay-notification-modal"></div>
      <form id="notification-form"></form>
    `;

    document.documentElement.replaceChild(replacementBody, document.body);

    dispatchHtmxLoad();
    document.getElementById("open-notification-modal")?.click();

    expect(document.getElementById("notification-modal")?.classList.contains("hidden")).to.equal(false);
  });
});
