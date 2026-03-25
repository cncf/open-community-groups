/** Stubs native validity UI helpers used by form validation tests. */
export const stubValidityUi = (input) => {
  input.reportValidity = () => true;
  input.focus = () => {};
  input.blur = () => {};
};
