import { expect } from "@open-wc/testing";

import "/static/js/common/labels-editor.js";
import { initializeEventLabels } from "/static/js/dashboard/group/event-labels.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

const COLORS = ["#bfdbfe", "#fecaca"];
const LABELS = [
  { color: "#fecaca", event_label_id: "label-2", name: "Frontend" },
  { color: "#bfdbfe", event_label_id: "label-1", name: "Backend" },
];

describe("event labels", () => {
  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    resetDom();
  });

  it("applies the editor labels to the sessions section once the editor is defined", async () => {
    // Render the event page with saved labels.
    const { sessionsSection } = renderPage(LABELS);

    // Initialize the labels sync.
    initializeEventLabels(document.getElementById("event-page"));
    await waitForMicrotask();

    // Verify the sessions section receives the sorted named labels and ids.
    expect(sessionsSection.labels).to.deep.equal([
      { color: "#bfdbfe", event_label_id: "label-1", name: "Backend" },
      { color: "#fecaca", event_label_id: "label-2", name: "Frontend" },
    ]);
    expect(sessionsSection.labelIds).to.deep.equal(["label-1", "label-2"]);
  });

  it("forwards unsaved label edits and keeps blank rows in the ids", async () => {
    // Render and initialize the event page.
    const { labelsEditor, sessionsSection } = renderPage(LABELS);
    initializeEventLabels(document.getElementById("event-page"));
    await waitForMicrotask();

    // Blank the first label name in the editor.
    await labelsEditor.updateComplete;
    const nameInput = labelsEditor.querySelector('input[type="text"]');
    nameInput.value = "";
    nameInput.dispatchEvent(new Event("input", { bubbles: true }));

    // Verify blank labels stay in ids but leave the named labels.
    expect(sessionsSection.labels).to.deep.equal([
      { color: "#fecaca", event_label_id: "label-2", name: "Frontend" },
    ]);
    expect(sessionsSection.labelIds).to.deep.equal(["label-1", "label-2"]);
  });

  it("falls back to empty lists when a change event has no detail", async () => {
    // Render and initialize the event page.
    const { labelsEditor, sessionsSection } = renderPage(LABELS);
    initializeEventLabels(document.getElementById("event-page"));
    await waitForMicrotask();

    // Dispatch a labels change without payload.
    labelsEditor.dispatchEvent(new CustomEvent("labels-changed"));

    // Verify the sessions section is cleared.
    expect(sessionsSection.labels).to.deep.equal([]);
    expect(sessionsSection.labelIds).to.deep.equal([]);
  });

  it("binds the labels listener only once per page root", async () => {
    // Render the event page and count sessions labels updates.
    const { labelsEditor, sessionsSection } = renderPage(LABELS);
    const pageRoot = document.getElementById("event-page");
    let updates = 0;
    Object.defineProperty(sessionsSection, "labels", {
      configurable: true,
      get: () => [],
      set: () => {
        updates += 1;
      },
    });

    // Initialize twice and wait for the initial sync.
    initializeEventLabels(pageRoot);
    initializeEventLabels(pageRoot);
    await waitForMicrotask();
    updates = 0;

    // Dispatch one labels change.
    labelsEditor.dispatchEvent(new CustomEvent("labels-changed", { detail: { ids: [], labels: [] } }));

    // Verify one listener handled the change.
    expect(pageRoot.dataset.labelsReady).to.equal("true");
    expect(updates).to.equal(1);
  });

  it("ignores roots that are not elements or miss the labels markup", () => {
    // Render a page without the sessions section.
    document.body.innerHTML = '<div id="event-page"><labels-editor></labels-editor></div>';

    // Verify invalid roots are ignored without errors.
    expect(() => initializeEventLabels(document)).to.not.throw();
    expect(() => initializeEventLabels(null)).to.not.throw();
    expect(() => initializeEventLabels(document.getElementById("event-page"))).to.not.throw();
  });
});

/**
 * Renders an event page fixture with the labels editor and sessions section.
 * @param {Array<Object>} labels Saved labels.
 * @returns {{labelsEditor: HTMLElement, sessionsSection: HTMLElement}}
 */
const renderPage = (labels) => {
  document.body.innerHTML = `
    <div id="event-page">
      <labels-editor field-name="labels"></labels-editor>
      <sessions-section></sessions-section>
    </div>
  `;
  const labelsEditor = document.querySelector("labels-editor");
  labelsEditor.colors = COLORS;
  labelsEditor.setLabels(labels);

  return {
    labelsEditor,
    sessionsSection: document.querySelector("sessions-section"),
  };
};
