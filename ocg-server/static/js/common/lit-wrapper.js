import { LitElement } from "/static/vendor/js/lit-all.v3.3.1.min.js";

/**
 * Base wrapper class for Lit components that disables shadow DOM.
 * Allows components to use global Tailwind CSS styles.
 * @extends LitElement
 */
export class LitWrapper extends LitElement {
  constructor() {
    super();
    this._hasInitializedLightDomRoot = false;
  }

  /**
   * Clears restored light DOM once before Lit performs the first render.
   */
  connectedCallback() {
    if (!this._hasInitializedLightDomRoot) {
      this._hasInitializedLightDomRoot = true;

      if (this.childNodes.length > 0) {
        this.replaceChildren();
      }
    }

    super.connectedCallback();
  }

  /**
   * Creates the render root for the component.
   * Disables shadow DOM to enable global CSS access.
   * @returns {LitWrapper} The component instance as render root
   */
  createRenderRoot() {
    return this;
  }
}
