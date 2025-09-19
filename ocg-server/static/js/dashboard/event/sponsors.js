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
    showLevelModal: { type: Boolean },
    pendingSponsor: { type: Object },
    pendingLevel: { type: String },
  };

  constructor() {
    super();
    this.sponsors = [];
    this.selectedSponsors = [];
    this.enteredValue = "";
    this.visibleOptions = [];
    this.visibleDropdown = false;
    this.activeIndex = null;
    this.showLevelModal = false;
    this.pendingSponsor = null;
    this.pendingLevel = "";
  }

  connectedCallback() {
    super.connectedCallback();

    // Parse JSON provided via attributes when needed
    this._ensureArrayProp("sponsors");
    this._ensureArrayProp("selectedSponsors");

    // Normalize selected sponsors into full objects
    this._initializeSelectedFromIds();

    window.addEventListener("mousedown", this._handleClickOutside);

    // Validate levels before submitting add/update event forms
    const addBtn = document.getElementById("add-event-button");
    const updateBtn = document.getElementById("update-event-button");
    const beforeSubmit = (e) => {
      if (!this._requireLevels()) {
        e.preventDefault();
        e.stopPropagation();
        const missing = (this.selectedSponsors || []).find((s) => !s.level || !String(s.level).trim().length);
        if (missing) {
          this.pendingSponsor = missing;
          this.pendingLevel = "";
          this.showLevelModal = true;
        }
      }
    };
    if (addBtn) addBtn.addEventListener("click", beforeSubmit, true);
    if (updateBtn) updateBtn.addEventListener("click", beforeSubmit, true);
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
      // Open level modal for the selected sponsor
      this.pendingSponsor = sponsor;
      this.pendingLevel = "";
      this.showLevelModal = true;
    } else {
      this._cleanEnteredValue();
    }
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
        </div>
      </div>
    </li>`;
  }

  /**
   * Confirms adding the pending sponsor with provided level.
   * @private
   */
  _confirmAddSponsorLevel() {
    if (!this.pendingSponsor) return;
    const levelVal = (this.pendingLevel || "").trim();
    if (!levelVal) {
      return; // guard; button disabled when empty
    }
    const id = this.pendingSponsor.group_sponsor_id;
    const exists = (this.selectedSponsors || []).some((s) => s.group_sponsor_id === id);
    if (exists) {
      this.selectedSponsors = (this.selectedSponsors || []).map((s) =>
        s.group_sponsor_id === id ? { ...s, level: levelVal } : s,
      );
    } else {
      const sponsor = { ...this.pendingSponsor, level: levelVal };
      this.selectedSponsors = [...(this.selectedSponsors || []), sponsor];
    }
    this._closeLevelModal();
    this._cleanEnteredValue();
  }

  /**
   * Closes the level modal and clears pending state.
   * @private
   */
  _closeLevelModal() {
    this.showLevelModal = false;
    this.pendingSponsor = null;
    this.pendingLevel = "";
    // Also close suggestions dropdown and reset search state
    this._cleanEnteredValue();
  }

  /**
   * Validates that all selected sponsors have non-empty levels.
   * @returns {boolean}
   * @private
   */
  _requireLevels() {
    const items = this.selectedSponsors || [];
    return items.every((s) => s && s.group_sponsor_id && s.level && String(s.level).trim().length > 0);
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
                : html`<div class="px-8 py-4 text-sm/6 text-stone-600 font-semibold">No sponsors found</div>`}
            </div>
          </div>
        </div>

        ${this.selectedSponsors && this.selectedSponsors.length > 0
          ? html`<div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4 mt-2 w-full xl:w-2/3">
              ${this.selectedSponsors.map(
                (s, i) =>
                  html`<div
                      class="inline-flex items-center gap-3 rounded-xl border border-stone-200 bg-white p-4 w-full"
                    >
                      <div
                        class="relative flex items-center justify-center size-18 shrink-0 rounded-lg bg-white border border-stone-200 overflow-hidden"
                      >
                        <img
                          src="${s.logo_url}"
                          alt="${s.name} logo"
                          class="size-16 object-contain"
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
                        <div class="text-xs uppercase tracking-wide text-stone-600 truncate mt-1.5">
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
                    <input
                      type="hidden"
                      name="sponsors[${i}][group_sponsor_id]"
                      value="${s.group_sponsor_id}"
                    />
                    <input type="hidden" name="sponsors[${i}][level]" value="${s.level || ""}" />`,
              )}
            </div>`
          : ""}
        ${this.showLevelModal
          ? html`
              <div class="fixed inset-0 z-20 flex items-center justify-center">
                <div class="absolute inset-0 bg-black/30" @click=${() => this._closeLevelModal()}></div>
                <div
                  class="relative bg-white rounded-lg shadow-xl border border-stone-200 w-[90%] max-w-md p-6"
                >
                  <div class="text-lg font-semibold text-stone-900 mb-4">Add sponsor level</div>
                  <div class="flex items-center gap-3 mb-4">
                    <div
                      class="relative flex items-center justify-center size-10 shrink-0 rounded-lg bg-white border border-stone-200 overflow-hidden"
                    >
                      <img
                        src="${this.pendingSponsor?.logo_url || ""}"
                        alt="${this.pendingSponsor?.name || ""} logo"
                        class="size-8 object-contain"
                        loading="lazy"
                      />
                    </div>
                    <div class="text-sm font-medium text-stone-900 truncate">
                      ${this.pendingSponsor?.name || ""}
                    </div>
                  </div>
                  <label class="form-label" for="sponsor-level-input">Level</label>
                  <input
                    id="sponsor-level-input"
                    type="text"
                    class="input-primary mt-2 w-full"
                    placeholder="Gold, Silver, Bronze, ..."
                    .value=${this.pendingLevel}
                    @input=${(e) => (this.pendingLevel = e.target.value || "")}
                  />
                  <div class="mt-6 flex items-center justify-end gap-3">
                    <button type="button" class="btn-primary-outline" @click=${() => this._closeLevelModal()}>
                      Cancel
                    </button>
                    <button
                      type="button"
                      class="btn-primary"
                      ?disabled=${!(this.pendingLevel || "").trim().length}
                      @click=${() => this._confirmAddSponsorLevel()}
                    >
                      Add
                    </button>
                  </div>
                </div>
              </div>
            `
          : ""}
      </div>
    `;
  }
}

customElements.define("sponsors-section", SponsorsSection);
