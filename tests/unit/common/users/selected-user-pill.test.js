import { expect } from "@open-wc/testing";

import "/static/js/common/users/selected-user-pill.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";

describe("selected-user-pill", () => {
  useMountedElementsCleanup("selected-user-pill");

  it("renders a compact removable user pill", async () => {
    // Render the selected-user-pill fixture.
    const element = await mountLitComponent("selected-user-pill", {
      user: {
        name: "Ada Lovelace",
        username: "ada",
        photo_url: "https://example.com/ada.png",
      },
      featured: true,
      removeLabel: "Remove speaker",
    });

    // The pill shows the user details and remove label.
    expect(element.textContent).to.include("Ada Lovelace");
    expect(element.querySelector("logo-image")?.getAttribute("placeholder")).to.equal("AL");
    expect(element.querySelector(".icon-star")).to.not.equal(null);
    expect(element.querySelector("button")?.getAttribute("aria-label")).to.equal("Remove speaker");
  });

  it("keeps speaker chip spacing in the speaker variant", async () => {
    // Render the selected-user-pill speaker variant.
    const element = await mountLitComponent("selected-user-pill", {
      user: { name: "Grace Hopper", username: "grace" },
      variant: "speaker",
    });

    // Speaker layout uses the wider chip spacing and default avatar text size.
    expect(element.firstElementChild.className).to.include("pe-2");
    expect(element.querySelector("logo-image")?.getAttribute("font-size")).to.equal(null);
    expect(element.querySelector("span")?.className).not.to.include("pe-1");
  });

  it("emits remove when the remove button is clicked", async () => {
    // Render the selected-user-pill fixture and capture remove events.
    const user = { name: "Grace Hopper", username: "grace" };
    const element = await mountLitComponent("selected-user-pill", { user });
    let removeEvent = null;

    element.addEventListener("remove", (event) => {
      removeEvent = event;
    });

    // Click the remove button.
    element.querySelector("button").click();

    // The remove event can be handled by parents outside the component.
    expect(removeEvent.detail).to.equal(null);
    expect(removeEvent.bubbles).to.equal(true);
    expect(removeEvent.composed).to.equal(true);
  });

  it("does not emit remove when disabled", async () => {
    // Render the selected-user-pill fixture in the disabled state.
    const element = await mountLitComponent("selected-user-pill", {
      user: { name: "Radia Perlman", username: "radia" },
      disabled: true,
    });
    let removeCalls = 0;

    element.addEventListener("remove", () => {
      removeCalls += 1;
    });

    // Click the disabled remove button.
    element.querySelector("button").click();

    // Disabled pills ignore remove requests.
    expect(removeCalls).to.equal(0);
  });
});
