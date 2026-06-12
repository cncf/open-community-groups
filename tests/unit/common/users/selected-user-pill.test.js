import { expect } from "@open-wc/testing";

import "/static/js/common/users/selected-user-pill.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";

describe("selected-user-pill", () => {
  useMountedElementsCleanup("selected-user-pill");

  it("renders a compact removable user pill", async () => {
    const element = await mountLitComponent("selected-user-pill", {
      user: {
        name: "Ada Lovelace",
        username: "ada",
        photo_url: "https://example.com/ada.png",
      },
      featured: true,
      removeLabel: "Remove speaker",
    });

    expect(element.textContent).to.include("Ada Lovelace");
    expect(element.querySelector("logo-image")?.getAttribute("placeholder")).to.equal("AL");
    expect(element.querySelector(".icon-star")).to.not.equal(null);
    expect(element.querySelector("button")?.getAttribute("aria-label")).to.equal("Remove speaker");
  });

  it("keeps speaker chip spacing in the speaker variant", async () => {
    const element = await mountLitComponent("selected-user-pill", {
      user: { name: "Grace Hopper", username: "grace" },
      variant: "speaker",
    });

    expect(element.firstElementChild.className).to.include("pe-2");
    expect(element.querySelector("logo-image")?.getAttribute("font-size")).to.equal(null);
    expect(element.querySelector("span")?.className).not.to.include("pe-1");
  });

  it("emits remove when the remove button is clicked", async () => {
    const user = { name: "Grace Hopper", username: "grace" };
    const element = await mountLitComponent("selected-user-pill", { user });
    let removeEvent = null;

    element.addEventListener("remove", (event) => {
      removeEvent = event;
    });

    element.querySelector("button").click();

    expect(removeEvent.detail).to.equal(null);
    expect(removeEvent.bubbles).to.equal(false);
    expect(removeEvent.composed).to.equal(false);
  });

  it("does not emit remove when disabled", async () => {
    const element = await mountLitComponent("selected-user-pill", {
      user: { name: "Radia Perlman", username: "radia" },
      disabled: true,
    });
    let removeCalls = 0;

    element.addEventListener("remove", () => {
      removeCalls += 1;
    });

    element.querySelector("button").click();

    expect(removeCalls).to.equal(0);
  });
});
