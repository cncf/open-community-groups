import { html } from "/static/vendor/js/lit-all.v3.2.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";

/**
 * Event sponsors selector.
 * Allows searching and selecting sponsors from the group's list and renders
 * hidden inputs with selected sponsor IDs for form submission.
 * @extends LitWrapper
 */
export class SponsorsSection extends LitWrapper {
  /**
   * Component properties
   * - sponsors: list of available group sponsors
   * - selectedSponsors: list of selected sponsor IDs (uuids)
   * - enteredValue: current search input value
   * - visibleOptions: filtered suggestions
   * - visibleDropdown: dropdown visibility flag
   * - activeIndex: active suggestion index
   */
  static properties = {
    sponsors: { type: Array },
    selectedSponsors: { type: Array, attribute: "selected-sponsors" },
    enteredValue: { type: String },
    visibleOptions: { type: Array },
    visibleDropdown: { type: Boolean },
    activeIndex: { type: Number },
  };

  constructor() {
    super();
    this.sponsors = [];
    this.selectedSponsors = [];
    this.enteredValue = "";
    this.visibleOptions = [];
    this.visibleDropdown = false;
    this.activeIndex = null;
  }

  connectedCallback() {
    super.connectedCallback();

    // Parse JSON provided via attributes when needed
    this._ensureArrayProp("sponsors");
    this._ensureArrayProp("selectedSponsors");

    // Normalize selected sponsors into full objects
    this._initializeSelectedFromIds();

    window.addEventListener("mousedown", this._handleClickOutside);
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    window.removeEventListener("mousedown", this._handleClickOutside);
  }

  /**
   * Ensures a property is an array by parsing JSON attribute if string.
   * @param {"sponsors"|"selectedSponsors"} prop
   * @private
   */
  _ensureArrayProp(prop) {
    const value = this[prop];
    if (typeof value === "string") {
      try {
        this[prop] = JSON.parse(value || "[]");
      } catch (_e) {
        this[prop] = [];
      }
    }
    if (!Array.isArray(this[prop])) {
      this[prop] = [];
    }
  }

  /**
   * Initializes selected sponsors list from provided IDs.
   * Accepts either an array of UUID strings or of full sponsor objects.
   * @private
   */
  _initializeSelectedFromIds() {
    if (this.selectedSponsors.length === 0) return;

    // If items are objects already, keep them; otherwise map IDs to objects
    const looksLikeId = (v) => typeof v === "string" || typeof v === "number";
    if (this.selectedSponsors.every((v) => looksLikeId(v))) {
      const byId = new Map(this.sponsors.map((s) => [s.group_sponsor_id, s]));
      this.selectedSponsors = this.selectedSponsors.map((id) => byId.get(id)).filter((s) => !!s);
    }
  }

  /**
   * Handles click outside to close the dropdown.
   * @param {MouseEvent} event
   * @private
   */
  _handleClickOutside = (event) => {
    if (!this.contains(event.target)) {
      this._cleanEnteredValue();
    }
  };

  /**
   * Filters available sponsors based on entered text and current selection.
   * @private
   */
  _filterOptions() {
    const term = (this.enteredValue || "").trim().toLowerCase();
    const baseOptions = this.sponsors || [];

    this.visibleOptions =
      term.length === 0 ? baseOptions : baseOptions.filter((s) => s.name.toLowerCase().includes(term));
    this.visibleDropdown = true;
    this.activeIndex = this.visibleOptions.length > 0 ? 0 : null;
  }

  /**
   * Handles search input changes.
   * @param {Event} event
   * @private
   */
  _onInputChange(event) {
    this.enteredValue = event.target.value || "";
    this._filterOptions();
  }

  /**
   * Shows full list on input focus (before typing).
   * @private
   */
  _onInputFocus() {
    this._filterOptions();
  }

  /**
   * Clears input and closes suggestion dropdown.
   * @private
   */
  _cleanEnteredValue() {
    this.enteredValue = "";
    this.visibleDropdown = false;
    this.visibleOptions = [];
    this.activeIndex = null;
  }

  /**
   * Keyboard navigation for suggestions.
   * @param {KeyboardEvent} event
   * @private
   */
  _handleKeyDown(event) {
    if (!this.visibleDropdown || this.visibleOptions.length === 0) return;

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault();
        if (this.activeIndex === null) this.activeIndex = 0;
        else this.activeIndex = (this.activeIndex + 1) % this.visibleOptions.length;
        break;
      case "ArrowUp":
        event.preventDefault();
        if (this.activeIndex === null) this.activeIndex = 0;
        else
          this.activeIndex = (this.activeIndex - 1 + this.visibleOptions.length) % this.visibleOptions.length;
        break;
      case "Enter":
        event.preventDefault();
        if (this.activeIndex !== null) {
          const item = this.visibleOptions[this.activeIndex];
          if (item) this._onSelect(item);
        }
        break;
      default:
        break;
    }
  }

  /**
   * Adds a sponsor to the selected list.
   * @param {Object} sponsor
   * @private
   */
  _onSelect(sponsor) {
    const exists = (this.selectedSponsors || []).some((s) => s.group_sponsor_id === sponsor.group_sponsor_id);
    if (!exists) {
      this.selectedSponsors = [...(this.selectedSponsors || []), sponsor];
    }
    this._cleanEnteredValue();
  }

  /**
   * Removes a sponsor from the selected list.
   * @param {string} sponsorId
   * @private
   */
  _onRemove(sponsorId) {
    this.selectedSponsors = (this.selectedSponsors || []).filter((s) => s.group_sponsor_id !== sponsorId);
  }

  /**
   * Renders a single suggestion item.
   * @param {Object} option
   * @param {number} index
   * @private
   */
  _renderOption(option, index) {
    const isActive = this.activeIndex === index;
    const isSelected = (this.selectedSponsors || []).some(
      (s) => s.group_sponsor_id === option.group_sponsor_id,
    );
    const rowClass = `flex items-center gap-3 px-4 py-2 ${
      isSelected ? "opacity-50 cursor-not-allowed bg-stone-50" : "hover:bg-stone-50 cursor-pointer"
    } ${isActive ? "bg-stone-50" : ""}`;
    return html`<li data-index="${index}">
      <div
        class="${rowClass}"
        aria-disabled="${isSelected ? "true" : "false"}"
        @click=${() => {
          if (!isSelected) this._onSelect(option);
        }}
        @mouseover=${() => (this.activeIndex = index)}
      >
        <div
          class="relative flex items-center justify-center h-9 w-9 shrink-0 rounded-full bg-white border border-stone-200 overflow-hidden"
        >
          <img
            src="${option.logo_url}"
            alt="${option.name} logo"
            class="h-6 w-6 object-contain"
            loading="lazy"
          />
        </div>
        <div class="flex-1 min-w-0">
          <div class="text-sm font-medium text-stone-900 truncate">${option.name}</div>
          <div class="text-xs uppercase tracking-wide text-stone-600 truncate">${option.level}</div>
        </div>
      </div>
    </li>`;
  }

  render() {
    return html`
      <div class="space-y-4">
        <div class="text-sm/6 text-stone-500">
          Select sponsors for your event from the group's sponsors list.
        </div>

        <div class="relative w-full xl:w-2/3">
          <div class="absolute top-3 start-0 flex items-center ps-3 pointer-events-none">
            <div class="svg-icon size-4 icon-search bg-stone-300"></div>
          </div>
          <input
            type="text"
            class="input-primary peer ps-9"
            placeholder="Search sponsors"
            autocomplete="off"
            autocorrect="off"
            autocapitalize="off"
            spellcheck="false"
            .value=${this.enteredValue}
            @input=${(e) => this._onInputChange(e)}
            @keydown=${(e) => this._handleKeyDown(e)}
            @focus=${() => this._onInputFocus()}
          />
          <div class="absolute end-1.5 top-1.5 peer-placeholder-shown:hidden">
            <button @click=${() => this._cleanEnteredValue()} type="button" class="cursor-pointer mt-[2px]">
              <div class="svg-icon size-5 bg-stone-400 hover:bg-stone-700 icon-close"></div>
            </button>
          </div>

          <div class="absolute z-10 start-0 end-0">
            <div
              class="${!this.visibleDropdown
                ? "hidden"
                : ""} bg-white divide-y divide-stone-100 rounded-lg shadow w-full border border-stone-200 mt-1"
            >
              ${this.visibleOptions && this.visibleOptions.length > 0
                ? html`<ul class="py-1 text-stone-700 overflow-auto max-h-80">
                    ${this.visibleOptions.map((opt, idx) => this._renderOption(opt, idx))}
                  </ul>`
                : html`<div class="px-8 py-4 text-sm/6 text-stone-600 italic">No sponsors found</div>`}
            </div>
          </div>
        </div>

        ${this.selectedSponsors && this.selectedSponsors.length > 0
          ? html`<div class="flex gap-2 mt-2 flex-wrap w-full xl:w-2/3">
              ${this.selectedSponsors.map(
                (s) =>
                  html`<div
                      class="inline-flex items-center gap-3 rounded-xl border border-stone-200 bg-stone-50 px-4 py-3 min-w-[200px]"
                    >
                      <div
                        class="relative flex items-center justify-center h-9 w-9 shrink-0 rounded-full bg-white border border-stone-200 overflow-hidden"
                      >
                        <img
                          src="${s.logo_url}"
                          alt="${s.name} logo"
                          class="h-6 w-6 object-contain"
                          loading="lazy"
                        />
                        <div class="fallback-icon hidden absolute inset-0 flex items-center justify-center">
                          <div class="svg-icon size-5 bg-amber-500 icon-handshake"></div>
                        </div>
                      </div>
                      <div class="leading-tight min-w-0 flex-1">
                        <div class="text-sm md:text-base font-semibold text-stone-900 truncate">
                          ${s.name}
                        </div>
                        <div class="text-xs uppercase tracking-wide text-stone-600 truncate">
                          ${s.level || ""}
                        </div>
                      </div>
                      <button
                        type="button"
                        class="p-1 rounded-full hover:bg-stone-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500"
                        aria-label="Remove ${s.name}"
                        title="Remove"
                        @click=${() => this._onRemove(s.group_sponsor_id)}
                      >
                        <div class="svg-icon size-4 icon-close bg-stone-600"></div>
                      </button>
                    </div>
                    <input type="hidden" name="sponsors[]" value="${s.group_sponsor_id}" />`,
              )}
            </div>`
          : ""}
      </div>
    `;
  }
}

customElements.define("sponsors-section", SponsorsSection);
