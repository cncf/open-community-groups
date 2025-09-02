import { html, repeat } from "/static/vendor/js/lit-all.v3.2.1.min.js";
import { isObjectEmpty } from "/static/js/common/common.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";

/**
 * Component for managing sponsor entries in events.
 * Supports adding, removing, and reordering sponsor items.
 * @extends LitWrapper
 */
export class SponsorsSection extends LitWrapper {
  /**
   * Component properties definition
   * @property {Array} sponsors - List of sponsor entries
   * Each entry contains:
   *  - id: Unique identifier
   *  - name: Sponsor organization name
   *  - tier: Sponsor tier level (gold, silver, bronze, etc.)
   *  - description: Sponsor description (markdown format)
   *  - website_url: Sponsor website URL
   *  - logo_url: Sponsor logo image URL (optional)
   */
  static properties = {
    sponsors: { type: Array },
  };

  constructor() {
    super();
    this.sponsors = [];
  }

  connectedCallback() {
    super.connectedCallback();
    this._initializeSponsorIds();
  }

  /**
   * Assigns unique IDs to sponsor entries.
   * Creates initial entry if none exist or array is empty.
   * @private
   */
  _initializeSponsorIds() {
    if (this.sponsors === null || this.sponsors.length === 0) {
      this.sponsors = [this._getData()];
    } else {
      this.sponsors = this.sponsors.map((item, index) => {
        return { ...this._getData(), ...item, id: index };
      });
    }
  }

  /**
   * Creates a new empty sponsor data object.
   * @returns {Object} Empty sponsor entry
   * @private
   */
  _getData = () => {
    let item = {
      id: this.sponsors ? this.sponsors.length : 0,
      name: "",
      level: "",
      website_url: "",
      logo_url: "",
    };

    return item;
  };

  /**
   * Adds a new sponsor entry at specified index.
   * @param {number} index - Position to insert new entry
   * @private
   */
  _addSponsorItem(index) {
    const currentSponsors = [...this.sponsors];
    currentSponsors.splice(index, 0, this._getData());

    this.sponsors = currentSponsors;
  }

  /**
   * Removes sponsor entry at specified index.
   * Ensures at least one empty entry remains.
   * @param {number} index - Position of entry to remove
   * @private
   */
  _removeSponsorItem(index) {
    const tmpSponsors = this.sponsors.filter((_, i) => i !== index);
    // If there are no more sponsor items, add a new one
    this.sponsors = tmpSponsors.length === 0 ? [this._getData()] : tmpSponsors;
  }

  /**
   * Updates sponsor data at specified index.
   * @param {Object} data - Updated sponsor data
   * @param {number} index - Index of entry to update
   * @private
   */
  _onDataChange = (data, index) => {
    this.sponsors[index] = data;
  };

  /**
   * Renders a sponsor entry with controls.
   * @param {number} index - Entry index
   * @param {Object} sponsor - Sponsor data
   * @returns {import('lit').TemplateResult} Entry template
   * @private
   */
  _getSponsorForm(index, sponsor) {
    const hasSingleSponsorItem = this.sponsors.length === 1;

    return html`<div class="mt-10">
      <div class="flex w-full xl:w-2/3">
        <div class="flex flex-col space-y-3 me-3">
          <div>
            <button
              @click=${() => this._addSponsorItem(index)}
              type="button"
              class="cursor-pointer p-2 border border-stone-200 hover:bg-stone-100 rounded-full"
              title="Add above"
            >
              <div class="svg-icon size-4 icon-plus-top bg-stone-600"></div>
            </button>
          </div>
          <div>
            <button
              @click=${() => this._addSponsorItem(index + 1)}
              type="button"
              class="cursor-pointer p-2 border border-stone-200 hover:bg-stone-100 rounded-full"
              title="Add below"
            >
              <div class="svg-icon size-4 icon-plus-bottom bg-stone-600"></div>
            </button>
          </div>
          <div>
            <button
              @click=${() => this._removeSponsorItem(index)}
              type="button"
              class="cursor-pointer p-2 border border-stone-200 hover:bg-stone-100 rounded-full"
              title="${hasSingleSponsorItem ? "Clean" : "Delete"}"
            >
              <div
                class="svg-icon size-4 icon-${hasSingleSponsorItem ? "eraser" : "trash"} bg-stone-600"
              ></div>
            </button>
          </div>
        </div>
        <sponsor-item
          .data=${sponsor}
          .index=${index}
          .onDataChange=${this._onDataChange}
          class="w-full"
        ></sponsor-item>
      </div>
    </div>`;
  }

  render() {
    return html` <div class="text-sm/6 text-stone-500">
        Add sponsors for your event. You can add additional sponsors by clicking on the
        <span class="font-semibold">+</span> buttons on the left of the card (
        <div class="inline-block svg-icon size-4 icon-plus-top bg-stone-600 relative -bottom-[2px]"></div>
        to add the new sponsor above,
        <div class="inline-block svg-icon size-4 icon-plus-bottom bg-stone-600 relative -bottom-[2px]"></div>
        to add it below). Sponsors will be displayed in the order provided.
      </div>
      <div id="sponsors-section">
        ${repeat(
          this.sponsors,
          (s) => s.id,
          (s, index) => this._getSponsorForm(index, s),
        )}
      </div>`;
  }
}
customElements.define("sponsors-section", SponsorsSection);

/**
 * Individual sponsor entry component.
 * Handles form inputs and validation for a single sponsor item.
 * @extends LitWrapper
 */
class SponsorItem extends LitWrapper {
  /**
   * Component properties definition
   * @property {Object} data - Sponsor entry data
   * @property {number} index - Position of the entry in the list
   * @property {boolean} isObjectEmpty - Indicates if the data object is empty
   * @property {Function} onDataChange - Callback function to notify parent component of changes
   */
  static properties = {
    data: { type: Object },
    index: { type: Number },
    isObjectEmpty: { type: Boolean },
    onDataChange: { type: Function },
  };

  constructor() {
    super();
    this.data = {
      id: 0,
      name: "",
      level: "",
      website_url: "",
      logo_url: "",
    };
    this.index = 0;
    this.isObjectEmpty = true;
    this.onDataChange = () => {};
  }

  connectedCallback() {
    super.connectedCallback();
    this.isObjectEmpty = isObjectEmpty(this.data);
  }

  /**
   * Handles input field changes.
   * @param {Event} event - Input event
   * @private
   */
  _onInputChange = (event) => {
    const value = event.target.value;
    const name = event.target.dataset.name;

    this.data[name] = value;
    this.isObjectEmpty = isObjectEmpty(this.data);
    this.onDataChange(this.data, this.index);
  };

  render() {
    return html` <div
      class="grid grid-cols-1 gap-x-6 gap-y-8 sm:grid-cols-6 border-2 border-stone-200 border-dashed p-8 rounded-lg bg-stone-50/25 w-full"
    >
      <div class="col-span-3">
        <label class="form-label"> Organization Name <span class="asterisk">*</span> </label>
        <div class="mt-2">
          <input
            @input=${(e) => this._onInputChange(e)}
            data-name="name"
            type="text"
            name="sponsors[${this.index}][name]"
            class="input-primary"
            value="${this.data.name}"
            autocomplete="off"
            autocorrect="off"
            autocapitalize="off"
            spellcheck="false"
            ?required=${!this.isObjectEmpty}
          />
        </div>
      </div>

      <div class="col-span-3">
        <label class="form-label"> Sponsor Level <span class="asterisk">*</span> </label>
        <div class="mt-2">
          <input
            @input=${(e) => this._onInputChange(e)}
            data-name="level"
            type="text"
            name="sponsors[${this.index}][level]"
            class="input-primary"
            value="${this.data.level}"
            placeholder="e.g., Gold, Silver, Bronze, Partner"
            autocomplete="off"
            autocorrect="off"
            autocapitalize="off"
            spellcheck="false"
            ?required=${!this.isObjectEmpty}
          />
        </div>
      </div>

      <div class="col-span-full">
        <label class="form-label"> Logo URL <span class="asterisk">*</span> </label>
        <div class="mt-2">
          <input
            @input=${(e) => this._onInputChange(e)}
            data-name="logo_url"
            type="url"
            name="sponsors[${this.index}][logo_url]"
            class="input-primary"
            value="${this.data.logo_url}"
            placeholder="Sponsor's logo image URL"
            autocomplete="off"
            autocorrect="off"
            autocapitalize="off"
            spellcheck="false"
            ?required=${!this.isObjectEmpty}
          />
        </div>
      </div>

      <div class="col-span-full">
        <label class="form-label"> Website URL </label>
        <div class="mt-2">
          <input
            @input=${(e) => this._onInputChange(e)}
            data-name="website_url"
            type="url"
            name="sponsors[${this.index}][website_url]"
            class="input-primary"
            value="${this.data.website_url}"
            autocomplete="off"
            autocorrect="off"
            autocapitalize="off"
            spellcheck="false"
          />
        </div>
      </div>
    </div>`;
  }
}
customElements.define("sponsor-item", SponsorItem);
