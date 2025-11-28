import { html, repeat } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { computeUserInitials } from "/static/js/common/common.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import "/static/js/common/avatar-image.js";
import "/static/js/dashboard/event/session-speaker-modal.js";
import { normalizeSpeakers, speakerKey, hasSpeaker } from "/static/js/dashboard/event/speaker-utils.js";

/**
 * Shared speakers selector with featured flag support.
 * Handles selection via modal, chip rendering, and hidden inputs naming.
 * @extends LitWrapper
 */
export class SpeakersSelector extends LitWrapper {
  /**
   * Component properties definition.
   * @property {Array} selectedSpeakers - Current speakers list
   * @property {string} dashboardType - Dashboard context type
   * @property {string} fieldNamePrefix - Prefix for form input names
   * @property {boolean} showAddButton - Whether to show the add button
   * @property {string} label - Optional label text
   * @property {string} helpText - Optional helper text
   */
  static properties = {
    selectedSpeakers: { type: Array, attribute: "selected-speakers" },
    dashboardType: { type: String, attribute: "dashboard-type" },
    fieldNamePrefix: { type: String, attribute: "field-name-prefix" },
    showAddButton: { type: Boolean, attribute: "show-add-button" },
    label: { type: String },
    helpText: { type: String, attribute: "help-text" },
  };

  constructor() {
    super();
    this.selectedSpeakers = [];
    this.dashboardType = "group";
    this.fieldNamePrefix = "speakers";
    this.showAddButton = false;
    this.label = "Speakers";
    this.helpText = "Add speakers or presenters.";
  }

  connectedCallback() {
    super.connectedCallback();
    this.selectedSpeakers = normalizeSpeakers(this.selectedSpeakers);
  }

  _getSpeakers() {
    return Array.isArray(this.selectedSpeakers) ? this.selectedSpeakers : [];
  }

  /**
   * Updates internal speakers list and emits change event.
   * @param {Array} nextSpeakers - Updated speakers array
   */
  _setSpeakers(nextSpeakers) {
    this.selectedSpeakers = normalizeSpeakers(nextSpeakers);
    this.requestUpdate();
    this._emitSpeakersChanged();
  }

  /**
   * Emits a speakers-changed event with current list.
   * @private
   */
  _emitSpeakersChanged() {
    this.dispatchEvent(
      new CustomEvent("speakers-changed", {
        detail: { speakers: this._getSpeakers() },
        bubbles: true,
        composed: true,
      }),
    );
  }

  /**
   * Opens the speaker modal with duplicate ids disabled.
   * @private
   */
  _openSpeakerModal = () => {
    const modal = this.querySelector("session-speaker-modal");
    if (!modal) return;
    modal.disabledUserIds = this._getSpeakers().map((speaker) => speaker.user_id);
    modal.dashboardType = this.dashboardType;
    if (typeof modal.open === "function") modal.open();
  };

  /**
   * Adds a selected speaker from modal if not duplicated.
   * @param {CustomEvent} event
   * @private
   */
  _handleSpeakerSelected = (event) => {
    const user = event.detail?.user;
    if (!user || hasSpeaker(this._getSpeakers(), user)) return;
    const featured = !!event.detail?.featured;
    this._setSpeakers([...this._getSpeakers(), { ...user, featured }]);
  };

  /**
   * Removes a speaker chip by matching key.
   * @param {Object} speaker
   * @private
   */
  _removeSpeaker = (speaker) => {
    if (!speaker) return;
    const target = speakerKey(speaker);
    const nextSpeakers = this._getSpeakers().filter((item) => speakerKey(item) !== target);
    this._setSpeakers(nextSpeakers);
  };

  /**
   * Renders a chip with avatar, star, and remove action.
   * @param {Object} speaker
   * @returns {import("lit").TemplateResult}
   * @private
   */
  _renderSpeakerChip(speaker) {
    const initials = computeUserInitials(speaker.name, speaker.username, 2);
    return html`
      <div class="inline-flex items-center gap-2 bg-stone-100 rounded-full ps-1 pe-2 py-1">
        <avatar-image
          image-url=${speaker.photo_url || ""}
          placeholder=${initials}
          size="size-[24px]"
          hide-border
        ></avatar-image>
        ${speaker.featured ? html`<div class="svg-icon size-3 icon-star bg-amber-500"></div>` : ""}
        <span class="text-sm text-stone-700">${speaker.name || speaker.username}</span>
        <button
          type="button"
          class="p-1 hover:bg-stone-200 rounded-full transition-colors"
          title="Remove speaker"
          @click=${() => this._removeSpeaker(speaker)}
        >
          <div class="svg-icon size-3 icon-close bg-stone-600"></div>
        </button>
      </div>
    `;
  }

  /**
   * Renders chips list or empty state message.
   * @param {Array} speakers
   * @returns {import("lit").TemplateResult}
   * @private
   */
  _renderSpeakerChips(speakers) {
    if (!speakers.length) {
      return html`<div class="mt-3 text-sm text-stone-500">No speakers added yet.</div>`;
    }
    return html`
      <div class="mt-3 flex flex-wrap gap-2 w-full">
        ${repeat(
          speakers,
          (speaker, index) => `${speakerKey(speaker) || index}`,
          (speaker) => this._renderSpeakerChip(speaker),
        )}
      </div>
    `;
  }

  /**
   * Renders hidden inputs for form submission.
   * @param {Array} speakers
   * @returns {import("lit").TemplateResult}
   * @private
   */
  _renderHiddenInputs(speakers) {
    if (!speakers.length) return html``;
    return html`
      ${speakers.map(
        (speaker, index) => html`
          <input type="hidden" name="${this.fieldNamePrefix}[${index}][user_id]" value=${speaker.user_id} />
          <input
            type="hidden"
            name="${this.fieldNamePrefix}[${index}][featured]"
            value=${speaker.featured ? "true" : "false"}
          />
        `,
      )}
    `;
  }

  render() {
    const speakers = this._getSpeakers();
    return html`
      <div class="w-full">
        <div class="flex items-center justify-between gap-4 flex-wrap w-full">
          <label class="form-label m-0">${this.label}</label>
          ${this.showAddButton
            ? html`<button type="button" class="btn-secondary" @click=${this._openSpeakerModal}>
                Add speaker
              </button>`
            : ""}
        </div>

        ${this.helpText ? html`<p class="text-sm text-stone-500 mt-1">${this.helpText}</p>` : ""}
        ${this._renderSpeakerChips(speakers)} ${this._renderHiddenInputs(speakers)}

        <session-speaker-modal
          dashboard-type=${this.dashboardType}
          .disabledUserIds=${speakers.map((speaker) => speaker.user_id)}
          @speaker-selected=${this._handleSpeakerSelected}
        ></session-speaker-modal>
      </div>
    `;
  }
}

customElements.define("speakers-selector", SpeakersSelector);
