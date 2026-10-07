import { expect } from "@open-wc/testing";

import "/static/js/common/form-validation.js";
import "/static/js/common/labels-editor.js";
import {
  mountLitComponent,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** Renders the editor inside a form so submitted values can be read. */
const renderEditorInForm = async (properties = {}) => {
  document.body.innerHTML = '<form id="labels-form"></form>';
  const form = document.getElementById("labels-form");
  const element = document.createElement("labels-editor");
  Object.assign(element, { colors: ["blue", "green"], ...properties });
  form.append(element);
  await element.updateComplete;
  return { element, form };
};

/** Types a value into a label name input. */
const typeName = async (element, input, value) => {
  input.value = value;
  input.dispatchEvent(new Event("input", { bubbles: true }));
  await element.updateComplete;
};

/** Returns the submitted entries of the labels form. */
const submittedEntries = (form) => Array.from(new FormData(form).entries());

describe("labels-editor", () => {
  useMountedElementsCleanup("labels-editor");

  it("normalizes and sorts the initial label rows", async () => {
    // Render the labels-editor fixture.
    const element = await mountLitComponent("labels-editor", {
      colors: ["blue", "green"],
      labels: [
        { event_label_id: "label-2", name: "Frontend", color: "green" },
        { event_label_id: "label-1", name: "Backend", color: "invalid" },
        { event_label_id: "label-3", name: "", color: "blue" },
      ],
    });

    // The editor keeps only named labels sorted by name, with their ids.
    expect(element._rows.map((row) => row.name)).to.deep.equal(["Backend", "Frontend"]);
    expect(element.getIds()).to.deep.equal(["label-1", "label-2"]);
    expect(element._rows.map((row) => row.is_new)).to.deep.equal([false, false]);
    expect(element._rows[0].color).to.equal("blue");
  });

  it("submits saved labels with their ids and one presence marker", async () => {
    // Render saved labels inside a form.
    const { element, form } = await renderEditorInForm({
      labels: [{ event_label_id: "label-1", name: "Backend", color: "blue" }],
    });

    // Verify the saved label submits its id without the new marker.
    expect(submittedEntries(form)).to.deep.equal([
      ["labels_present", "true"],
      ["labels[0][color]", "blue"],
      ["labels[0][event_label_id]", "label-1"],
      ["labels[0][name]", "Backend"],
    ]);
    expect(element.querySelector("#label-name-label-1").required).to.equal(true);
  });

  it("gives new rows stable random ids and submits them as new once named", async () => {
    // Render an empty editor with one starter row.
    const { element, form } = await renderEditorInForm();
    const [starterId] = element.getIds();

    // The blank starter row is valid and not submitted.
    expect(starterId).to.match(UUID_PATTERN);
    expect(element._rows[0].is_new).to.equal(true);
    expect(form.checkValidity()).to.equal(true);
    expect(submittedEntries(form)).to.deep.equal([["labels_present", "true"]]);

    // Name the starter row.
    await typeName(element, element.querySelector('input[type="text"]'), "  Workshops ");

    // The id stays the same and the row is submitted as new.
    expect(element.getIds()).to.deep.equal([starterId]);
    expect(submittedEntries(form)).to.deep.equal([
      ["labels_present", "true"],
      ["labels[0][color]", "blue"],
      ["labels[0][event_label_id]", starterId],
      ["labels[0][is_new]", "true"],
      ["labels[0][name]", "Workshops"],
    ]);
  });

  it("marks copied labels without ids as new", async () => {
    // Render an editor and copy labels from another event.
    const { element, form } = await renderEditorInForm();
    element.setLabels([
      { color: "green", name: "Frontend" },
      { color: "blue", name: "Backend" },
    ]);
    await element.updateComplete;

    // Copied labels get new ids and are submitted as new labels.
    const ids = element.getIds();
    expect(ids).to.have.length(2);
    ids.forEach((id) => expect(id).to.match(UUID_PATTERN));
    expect(new Set(ids).size).to.equal(2);
    expect(element._rows.map((row) => row.is_new)).to.deep.equal([true, true]);
    expect(new FormData(form).getAll("labels[0][is_new]")).to.deep.equal(["true"]);
    expect(new FormData(form).getAll("labels[1][is_new]")).to.deep.equal(["true"]);
  });

  it("blocks blank names on saved labels without dropping their ids", async () => {
    // Render a saved label inside a form.
    const { element, form } = await renderEditorInForm({
      labels: [{ event_label_id: "label-1", name: "Backend", color: "blue" }],
    });
    const input = element.querySelector("#label-name-label-1");

    // Replace the name with whitespace only.
    await typeName(element, input, "   ");

    // The row is invalid while its hidden id input is still rendered.
    expect(input.checkValidity()).to.equal(false);
    expect(input.validationMessage).to.equal("Label name is required");
    expect(form.checkValidity()).to.equal(false);
    expect(new FormData(form).get("labels[0][event_label_id]")).to.equal("label-1");
    expect(element.getLabels()).to.deep.equal([]);
    expect(element.getIds()).to.deep.equal(["label-1"]);

    // Fix the name.
    await typeName(element, input, "Backend APIs");

    // Validity is restored with the same id.
    expect(input.checkValidity()).to.equal(true);
    expect(form.checkValidity()).to.equal(true);
    expect(new FormData(form).get("labels[0][event_label_id]")).to.equal("label-1");
    expect(new FormData(form).get("labels[0][name]")).to.equal("Backend APIs");
  });

  it("keeps blank saved names invalid when form validation is wired", async () => {
    // Render a saved label inside a form wired by the shared form validation.
    const { element, form } = await renderEditorInForm({
      labels: [{ event_label_id: "label-1", name: "Backend", color: "blue" }],
    });
    form.dispatchEvent(new CustomEvent("htmx:load", { bubbles: true }));
    const input = element.querySelector("#label-name-label-1");

    // Replace the name with whitespace only and leave the field.
    await typeName(element, input, "   ");
    input.dispatchEvent(new Event("change", { bubbles: true }));

    // The required-field wiring keeps the editor validity message.
    expect(input.validationMessage).to.equal("Label name is required");
    expect(form.checkValidity()).to.equal(false);
  });

  it("deletes labels only through the trash button", async () => {
    // Render two saved labels.
    const { element, form } = await renderEditorInForm({
      labels: [
        { event_label_id: "label-1", name: "Backend", color: "blue" },
        { event_label_id: "label-2", name: "Frontend", color: "green" },
      ],
    });

    // Clearing a name keeps the label.
    await typeName(element, element.querySelector("#label-name-label-1"), "");
    expect(element.getIds()).to.deep.equal(["label-1", "label-2"]);

    // Remove the first label with its trash button.
    element.querySelectorAll('button[aria-label="Remove label"]')[0].click();
    await element.updateComplete;

    // Only the remaining label is submitted.
    expect(element.getIds()).to.deep.equal(["label-2"]);
    expect(new FormData(form).getAll("labels[0][event_label_id]")).to.deep.equal(["label-2"]);
    expect(form.checkValidity()).to.equal(true);
  });

  it("adds rows, updates color, and keeps one empty row after removals", async () => {
    // Render the labels-editor fixture.
    const element = await mountLitComponent("labels-editor", {
      colors: ["blue", "green"],
      labels: [],
    });

    // Add a row, update its color, and remove rows back to one draft.
    element._addRow();
    const rowId = element._rows[1].event_label_id;
    element._setRowColor(rowId, "green");
    expect(element._rows[1].color).to.equal("green");
    element._removeRow(element._rows[0].event_label_id);
    element._removeRow(rowId);
    await element.updateComplete;

    // The editor falls back to one empty new row after removals.
    expect(element._rows).to.have.length(1);
    expect(element._rows[0].name).to.equal("");
    expect(element._rows[0].is_new).to.equal(true);
    expect(element.querySelector('button[aria-label="Remove label"]').disabled).to.equal(true);
  });

  it("dispatches labels-changed with named labels and every row id", async () => {
    // Render a saved label and track change events.
    const { element } = await renderEditorInForm({
      labels: [{ event_label_id: "label-1", name: "Backend", color: "blue" }],
    });
    const details = [];
    element.addEventListener("labels-changed", (event) => details.push(event.detail));

    // Add a blank row and blank the saved label.
    element.querySelector(".btn-primary-outline").click();
    await element.updateComplete;
    await typeName(element, element.querySelector("#label-name-label-1"), " ");

    // Each change carries the named labels and every row id.
    const newId = element.getIds()[1];
    expect(details).to.deep.equal([
      {
        ids: ["label-1", newId],
        labels: [{ color: "blue", event_label_id: "label-1", name: "Backend" }],
      },
      { ids: ["label-1", newId], labels: [] },
    ]);
  });

  it("uses the configured max name length", async () => {
    // Render the editor with a custom max name length.
    const element = await mountLitComponent("labels-editor", { maxNameLength: 40 });

    // The name input uses the configured limit.
    expect(element.querySelector('input[type="text"]').getAttribute("maxlength")).to.equal("40");
  });

  it("preserves a custom legend across reconnects", async () => {
    // Create the labels-editor fixture element.
    const element = document.createElement("labels-editor");
    element.innerHTML = `
      <p slot="legend">
        Custom <a href="/docs/labels">legend</a>
      </p>
    `;
    document.body.append(element);

    // Render the custom legend into the form legend slot.
    await element.updateComplete;

    // The rendered legend keeps the custom link markup.
    let renderedLegend = element.querySelector(".form-legend");
    expect(renderedLegend?.innerHTML).to.contain('href="/docs/labels"');

    // Reconnect the fixture element.
    element.remove();
    document.body.append(element);

    // Request a component update after reconnecting.
    element.requestUpdate();
    await element.updateComplete;

    // The reconnected legend keeps the custom link markup.
    renderedLegend = element.querySelector(".form-legend");
    expect(renderedLegend?.innerHTML).to.contain('href="/docs/labels"');
  });

  it("clears the cached legend when the slotted legend is removed before reconnect", async () => {
    // Create the labels-editor fixture element.
    const element = document.createElement("labels-editor");
    element.innerHTML = `
      <p slot="legend">
        Custom <a href="/docs/labels">legend</a>
      </p>
    `;
    document.body.append(element);

    // Render the custom legend into the form legend slot.
    await element.updateComplete;

    // The rendered legend keeps the custom link markup.
    const renderedLegend = element.querySelector(".form-legend");
    expect(renderedLegend?.innerHTML).to.contain('href="/docs/labels"');

    // Reconnect the fixture element.
    element.remove();
    element.innerHTML = "<div></div>";
    document.body.append(element);

    // Re-render without the slotted legend and clear the cached legend HTML.
    await element.updateComplete;
    expect(element._legendHtml).to.equal("");
  });
});
