import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import {
  getLocationDisabledInputClasses,
  getLocationInputId,
  getLocationTextFieldDefinitions,
} from "/static/js/common/location-search-display.js";

const renderLocationTextField = ({ disabled, disabledClasses, field, getInputId, onInput }) => {
  const inputId = getInputId(field.fieldName);

  return html`
    <div class="${field.className}">
      <label for="${inputId}" class="form-label">${field.label}</label>
      <div class="mt-2">
        <input
          type="text"
          name="${field.fieldName}"
          id="${inputId}"
          class="input-primary ${disabledClasses}"
          autocomplete=${field.autocomplete === false ? "off" : "on"}
          autocorrect=${field.autocomplete === false ? "off" : "on"}
          autocapitalize=${field.autocomplete === false ? "off" : "on"}
          spellcheck=${field.autocomplete === false ? "false" : "true"}
          .value=${field.value}
          ?disabled=${disabled}
          @input=${(event) => onInput(field.handlerName, event)}
        />
      </div>
      <p class="form-legend">${field.legend}</p>
    </div>
  `;
};

/**
 * Renders generated location text fields.
 * @param {Object} state Location text field render state.
 * @returns {import('lit').TemplateResult}
 */
export const renderLocationTextFields = (state) => {
  const hiddenCountryCodeInput = state.countryCodeFieldName
    ? html`
        <input
          type="hidden"
          name="${state.countryCodeFieldName}"
          id="${getLocationInputId(state.componentId, state.countryCodeFieldName)}"
          .value=${state.countryCodeValue}
        />
      `
    : "";
  const disabledClasses = getLocationDisabledInputClasses(state.disabled);
  const textFields = getLocationTextFieldDefinitions(state);
  const getInputId = (inputName) => getLocationInputId(state.componentId, inputName);

  return html`
    <div class="mt-8 grid grid-cols-1 gap-x-6 gap-y-8 md:grid-cols-6 max-w-5xl">
      ${hiddenCountryCodeInput}
      ${textFields.map((field) =>
        renderLocationTextField({
          disabled: state.disabled,
          disabledClasses,
          field,
          getInputId,
          onInput: state.onInput,
        }),
      )}
    </div>
  `;
};
