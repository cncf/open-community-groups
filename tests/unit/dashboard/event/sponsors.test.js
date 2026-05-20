import { expect } from "@open-wc/testing";

import "/static/js/dashboard/event/sponsors.js";
import {
  mountLitComponent,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";

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
    // Render the fixture to check it normalizes selected sponsor ids into sponsor.
    const element = await mountLitComponent("sponsors-section", {
      sponsors,
      selectedSponsors: ["sponsor-2"],
    });

    // Confirm it normalizes selected sponsor ids into sponsor objects.
    expect(element.selectedSponsors).to.deep.equal([
      {
        group_sponsor_id: "sponsor-2",
        name: "Beta Compute",
        logo_url: "https://example.com/beta.png",
      },
    ]);
  });

  it("filters sponsors and opens the level modal from keyboard selection", async () => {
    // Render the fixture to check it filters sponsors and opens the level modal.
    const element = await mountLitComponent("sponsors-section", {
      sponsors,
    });

    // Run component methods to check it filters sponsors and opens the level modal.
    element._onInputChange({
      target: {
        value: "beta",
      },
    });
    await element.updateComplete;

    // Confirm it filters sponsors and opens the level modal from keyboard selection.
    expect(element.visibleDropdown).to.equal(true);
    expect(element.visibleOptions.map((item) => item.name)).to.deep.equal([
      "Beta Compute",
    ]);
    expect(element.activeIndex).to.equal(0);

    // Run component methods to check it filters sponsors and opens the level modal.
    element._handleKeyDown({
      key: "Enter",
      preventDefault() {},
    });
    await element.updateComplete;

    // Confirm it filters sponsors and opens the level modal from keyboard selection.
    expect(element.showLevelModal).to.equal(true);
    expect(element.pendingSponsor).to.deep.equal({
      group_sponsor_id: "sponsor-2",
      name: "Beta Compute",
      logo_url: "https://example.com/beta.png",
    });
  });

  it("adds the pending sponsor with its level and renders hidden inputs", async () => {
    // Render the fixture to check it adds the pending sponsor with its level and renders.
    const element = await mountLitComponent("sponsors-section", {
      sponsors,
    });

    // Run component methods to check it adds the pending sponsor with its level.
    element._onSelect(sponsors[0]);
    element.pendingLevel = "Gold";

    // Run component methods to check it adds the pending sponsor with its level.
    element._confirmAddSponsorLevel();
    await element.updateComplete;

    // Confirm it adds the pending sponsor with its level and renders hidden inputs.
    expect(element.selectedSponsors).to.deep.equal([
      {
        group_sponsor_id: "sponsor-1",
        name: "Acme Cloud",
        logo_url: "https://example.com/acme.png",
        level: "Gold",
      },
    ]);
    expect(element.showLevelModal).to.equal(false);
    expect(
      element.querySelector('input[name="sponsors[0][group_sponsor_id]"]')
        .value,
    ).to.equal("sponsor-1");
    expect(
      element.querySelector('input[name="sponsors[0][level]"]').value,
    ).to.equal("Gold");
  });

  it("blocks event submission when a selected sponsor is missing a level", async () => {
    // Prepare add event button to check it blocks event submission when a selected.
    const addEventButton = document.createElement("button");
    addEventButton.id = "add-event-button";
    document.body.append(addEventButton);

    // Render the fixture to check it blocks event submission when a selected sponsor.
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

    // Prepare submit event to check it blocks event submission when a selected sponsor.
    const submitEvent = new MouseEvent("click", {
      bubbles: true,
      cancelable: true,
    });
    const dispatchResult = addEventButton.dispatchEvent(submitEvent);
    await element.updateComplete;

    // Confirm it blocks event submission when a selected sponsor is missing a level.
    expect(dispatchResult).to.equal(false);
    expect(element.showLevelModal).to.equal(true);
    expect(element.pendingSponsor.group_sponsor_id).to.equal("sponsor-1");
    expect(element.pendingLevel).to.equal("");
  });
});
