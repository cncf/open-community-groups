import { expect } from "@open-wc/testing";

describe("dashboard group events list template", () => {
  it("places the add action after the tabs in the same responsive toolbar", async () => {
    const template = await loadTemplate();
    const document = new DOMParser().parseFromString(template, "text/html");
    const button = document.querySelector("#add-event-button");
    const tabs = document.querySelector("#upcoming-tab").closest("ul");
    const toolbar = tabs.parentElement;

    // Keep the action outside the tab list but within the same toolbar.
    expect(button.parentElement).to.equal(toolbar);
    expect(tabs.nextElementSibling).to.equal(button);
    expect(toolbar.classList.contains("sm:flex-row")).to.equal(true);
    expect(toolbar.classList.contains("sm:justify-between")).to.equal(true);
    expect(toolbar.classList.contains("flex-col")).to.equal(true);
    expect(toolbar.classList.contains("gap-3")).to.equal(true);
    expect(toolbar.classList.contains("my-5")).to.equal(true);
    expect(button.classList.contains("sm:mb-3")).to.equal(true);
    expect(button.classList.contains("shrink-0")).to.equal(true);
  });

  it("preserves add navigation and role restrictions", async () => {
    const template = await loadTemplate();
    const button = template.match(/<button id="add-event-button"[\s\S]*?<\/button>/)[0];

    expect(button).to.include('hx-get="/dashboard/group/events/add"');
    expect(button).to.include('hx-target="#dashboard-content"');
    expect(button).to.include('hx-replace-url="/dashboard/group?tab=events"');
    expect(button).to.include('hx-indicator="#dashboard-spinner"');
    expect(button).to.match(
      /{% if !can_manage_events -%}\s+disabled title="Your role cannot add events\."\s+{% endif -%}/,
    );
  });
});

/** Loads the group events list template. */
const loadTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/group/events_list.html");
  expect(response.ok).to.equal(true);
  return response.text();
};
