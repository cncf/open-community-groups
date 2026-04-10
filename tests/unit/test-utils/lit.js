import { resetDom } from "/tests/unit/test-utils/dom.js";

/** Mounts a Lit element with the given properties and waits for its first render. */
export const mountLitComponent = async (tagName, properties = {}) => {
  const element = document.createElement(tagName);
  Object.assign(element, properties);
  document.body.append(element);
  await element.updateComplete;
  return element;
};

/** Mounts a Lit element with attribute and property initialization. */
export const mountLitComponentWithAttributes = async (
  tagName,
  { attributes = {}, properties = {} } = {},
) => {
  const element = document.createElement(tagName);

  Object.entries(attributes).forEach(([name, value]) => {
    element.setAttribute(name, value);
  });

  Object.assign(element, properties);
  document.body.append(element);
  await element.updateComplete;
  return element;
};

/** Removes mounted component instances that match one or more selectors. */
export const removeMountedElements = (...selectors) => {
  selectors.forEach((selector) => {
    document.querySelectorAll(selector).forEach((element) => element.remove());
  });
};

/** Registers mounted-element cleanup and DOM reset hooks for a suite. */
export const useMountedElementsCleanup = (...selectors) => {
  afterEach(() => {
    removeMountedElements(...selectors);
    resetDom();
  });
};
