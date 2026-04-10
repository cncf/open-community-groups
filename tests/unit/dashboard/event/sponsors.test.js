import { expect } from "@open-wc/testing";

import "/static/js/dashboard/event/sponsors.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";

describe("sponsors-section", () => {
  const sponsors = [
    {
      group_sponsor_id: "sponsor-1",
      name: "Acme Cloud",
      logo_url: "https://example.com/acme.png",
    },
    {
      group_sponsor_id: "sponsor-2",
      name: "Beta Compute",
      logo_url: "https://example.com/beta.png",
    },
  ];

  useMountedElementsCleanup("sponsors-section");

  it("normalizes selected sponsor ids into sponsor objects", async () => {
    const element = await mountLitComponent("sponsors-section", {
      sponsors,
      selectedSponsors: ["sponsor-2"],
    });

    expect(element.selectedSponsors).to.deep.equal([
      {
        group_sponsor_id: "sponsor-2",
        name: "Beta Compute",
        logo_url: "https://example.com/beta.png",
      },
    ]);
  });

  it("filters sponsors and opens the level modal from keyboard selection", async () => {
    const element = await mountLitComponent("sponsors-section", {
      sponsors,
    });

    element._onInputChange({
      target: {
        value: "beta",
      },
    });
    await element.updateComplete;

    expect(element.visibleDropdown).to.equal(true);
    expect(element.visibleOptions.map((item) => item.name)).to.deep.equal(["Beta Compute"]);
    expect(element.activeIndex).to.equal(0);

    element._handleKeyDown({
      key: "Enter",
      preventDefault() {},
    });
    await element.updateComplete;

    expect(element.showLevelModal).to.equal(true);
    expect(element.pendingSponsor).to.deep.equal({
      group_sponsor_id: "sponsor-2",
      name: "Beta Compute",
      logo_url: "https://example.com/beta.png",
    });
  });

  it("adds the pending sponsor with its level and renders hidden inputs", async () => {
    const element = await mountLitComponent("sponsors-section", {
      sponsors,
    });

    element._onSelect(sponsors[0]);
    element.pendingLevel = "Gold";

    element._confirmAddSponsorLevel();
    await element.updateComplete;

    expect(element.selectedSponsors).to.deep.equal([
      {
        group_sponsor_id: "sponsor-1",
        name: "Acme Cloud",
        logo_url: "https://example.com/acme.png",
        level: "Gold",
      },
    ]);
    expect(element.showLevelModal).to.equal(false);
    expect(element.querySelector('input[name="sponsors[0][group_sponsor_id]"]').value).to.equal("sponsor-1");
    expect(element.querySelector('input[name="sponsors[0][level]"]').value).to.equal("Gold");
  });

  it("blocks event submission when a selected sponsor is missing a level", async () => {
    const addEventButton = document.createElement("button");
    addEventButton.id = "add-event-button";
    document.body.append(addEventButton);

    const element = await mountLitComponent("sponsors-section", {
      sponsors,
      selectedSponsors: [
        {
          group_sponsor_id: "sponsor-1",
          name: "Acme Cloud",
          logo_url: "https://example.com/acme.png",
          level: "",
        },
      ],
    });

    const submitEvent = new MouseEvent("click", {
      bubbles: true,
      cancelable: true,
    });
    const dispatchResult = addEventButton.dispatchEvent(submitEvent);
    await element.updateComplete;

    expect(dispatchResult).to.equal(false);
    expect(element.showLevelModal).to.equal(true);
    expect(element.pendingSponsor.group_sponsor_id).to.equal("sponsor-1");
    expect(element.pendingLevel).to.equal("");
  });
});
