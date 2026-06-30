import { html } from "/static/vendor/js/lit-all.v3.3.3.min.js";
import { computeUserInitials } from "/static/js/common/common.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import "/static/js/common/media/logo-image.js";
import { formatTimeDisplay } from "/static/js/dashboard/event/sessions/datetime.js";

/**
 * Session card component for displaying session summary.
 * @extends LitWrapper
 */
class SessionCard extends LitWrapper {
  /**
   * Component properties definition.
   * @property {Object} session Session entry displayed by the card.
   * @property {Array} sessionKinds Available session kinds.
   * @property {boolean} disabled Whether actions are disabled.
   */
  static properties = {
    session: { type: Object },
    sessionKinds: { type: Array },
    disabled: { type: Boolean },
  };

  constructor() {
    super();
    this.session = {};
    this.sessionKinds = [];
    this.disabled = false;
  }

  /**
   * Gets the display name for a session kind.
   * @param {string} kindId Session kind ID.
   * @returns {string} Display name.
   * @private
   */
  _getSessionKindDisplayName(kindId) {
    const kind = this.sessionKinds.find((k) => k.session_kind_id === kindId);
    return kind?.display_name || kindId || "";
  }

  _onEdit() {
    this.dispatchEvent(new CustomEvent("edit", { bubbles: true, composed: true }));
  }

  _onDelete() {
    this.dispatchEvent(new CustomEvent("delete", { bubbles: true, composed: true }));
  }

  /**
   * Renders speaker avatars with overflow indicator.
   * @returns {import("/static/vendor/js/lit-all.v3.3.3.min.js").TemplateResult|string}
   * @private
   */
  _renderSpeakerAvatars() {
    const speakers = this.session?.speakers || [];
    if (speakers.length === 0) return "";

    const sortedSpeakers = [...speakers].sort((a, b) => (b.featured ? 1 : 0) - (a.featured ? 1 : 0));
    const maxDisplay = 5;
    const displaySpeakers = sortedSpeakers.slice(0, maxDisplay);
    const remainingCount = speakers.length - maxDisplay;

    return html`
      <div class="flex items-center gap-1 ml-3 shrink-0">
        ${displaySpeakers.map((speaker) => {
          const initials = computeUserInitials(speaker.name, speaker.username, 1);
          return html`
            <div class="rounded-full">
              <logo-image
                image-url=${speaker.photo_url || ""}
                placeholder=${initials}
                size="size-5"
                font-size="text-[0.5rem]"
                hide-border
              ></logo-image>
            </div>
          `;
        })}
        ${
          remainingCount > 0
            ? html` <div class="text-xs font-semibold text-stone-700">+${remainingCount}</div> `
            : ""
        }
      </div>
    `;
  }

  render() {
    const { session } = this;
    const startTime = formatTimeDisplay(session.starts_at);
    const endTime = formatTimeDisplay(session.ends_at);
    const kindName = this._getSessionKindDisplayName(session.kind);

    return html`
      <div
        class="flex w-full min-w-0 items-center gap-4 p-4 border border-stone-200 rounded-lg bg-white hover:border-stone-300 transition-colors overflow-hidden"
      >
        <div class="flex items-center gap-3 shrink-0">
          <div class="text-right w-14">
            <div class="text-sm font-medium text-stone-700">${startTime || "--:--"}</div>
            <div class="text-sm text-stone-400">${endTime || html`&nbsp;`}</div>
          </div>
          <div class="w-0.5 h-10 bg-primary-300 rounded-full"></div>
        </div>

        <div class="flex-1 w-0 min-w-0 overflow-hidden">
          <div class="flex items-center min-w-0">
            <span class="font-medium text-stone-900 truncate">${session.name || "Untitled Session"}</span>
            ${this._renderSpeakerAvatars()}
          </div>
          <div class="text-sm text-stone-500 truncate w-full">
            ${kindName}${session.location ? html` · ${session.location}` : ""}
          </div>
        </div>

        <div class="flex items-center gap-3 shrink-0">
          <div class="flex items-center gap-1 shrink-0">
            <button
              type="button"
              class="p-2 rounded-full hover:bg-stone-100 transition-colors ${
                this.disabled ? "opacity-60 cursor-not-allowed" : ""
              }"
              title="Edit"
              @click=${this._onEdit}
              ?disabled=${this.disabled}
            >
              <div class="svg-icon size-4 icon-pencil bg-stone-600"></div>
            </button>
            <button
              type="button"
              class="p-2 rounded-full hover:bg-stone-100 transition-colors ${
                this.disabled ? "opacity-60 cursor-not-allowed" : ""
              }"
              title="Delete"
              @click=${this._onDelete}
              ?disabled=${this.disabled}
            >
              <div class="svg-icon size-4 icon-trash bg-stone-600"></div>
            </button>
          </div>
        </div>
      </div>
    `;
  }
}

customElements.define("session-card", SessionCard);
