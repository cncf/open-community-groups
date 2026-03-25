/** Mounts a Lit element with the given properties and waits for its first render. */
export const mountLitComponent = async (tagName, properties = {}) => {
  const element = document.createElement(tagName);
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
