import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";

/**
 * Renders a coordinate input field.
 * @param {Object} field Coordinate field state.
 * @returns {import("lit").TemplateResult}
 */
const renderCoordinateInput = (field) => html`
  <div>
    <label for="${field.inputId}" class="form-label">${field.label}</label>
    <div class="mt-2">
      <input
        type="number"
        step="any"
        id="${field.inputId}"
        name="${field.name}"
        class="input-primary ${field.disabledClasses}"
        .value=${field.value}
        ?disabled=${field.disabled}
        @input=${(event) => field.onInput(field.valueKey, event)}
      />
    </div>
  </div>
`;

/**
 * Renders latitude and longitude inputs.
 * @param {Object} state Coordinate input state.
 * @returns {import("lit").TemplateResult}
 */
export const renderLocationCoordinateInputs = (state) => html`
  <div class="grid grid-cols-2 gap-4 mt-6">
    ${renderCoordinateInput({
      disabled: state.disabled,
      disabledClasses: state.disabledClasses,
      inputId: state.latitudeId,
      label: "Latitude",
      name: state.latitudeName,
      onInput: state.onInput,
      value: state.latitudeValue,
      valueKey: "_latitudeValue",
    })}
    ${renderCoordinateInput({
      disabled: state.disabled,
      disabledClasses: state.disabledClasses,
      inputId: state.longitudeId,
      label: "Longitude",
      name: state.longitudeName,
      onInput: state.onInput,
      value: state.longitudeValue,
      valueKey: "_longitudeValue",
    })}
  </div>
`;
