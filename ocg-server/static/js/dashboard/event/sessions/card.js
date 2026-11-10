import { html } from "lit";
import { labelColorStyle, normalizeLabels } from "/static/js/common/labels.js";
import { computeUserInitials } from "/static/js/common/users/initials.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import "/static/js/common/media/logo-image.js";
import "/static/js/common/tooltip-panel.js";
import { formatTimeDisplay } from "/static/js/dashboard/event/sessions/datetime.js";

// Narrowest truncated chip kept next to the counter; below it every label moves to the tooltip.
const MIN_VISIBLE_CHIP_WIDTH = 48;

// Counter used to build unique labels tooltip ids.
let labelsTooltipCount = 0;

/**
 * Session card component for displaying session summary.
 * @extends LitWrapper
 */
class SessionCard extends LitWrapper {
  /**
   * Component properties definition.
   * @property {Object} session Session entry displayed by the card.
   * @property {Array} sessionKinds Available session kinds.
   * @property {Array} labels Named event labels.
   * @property {boolean} disabled Whether actions are disabled.
   */
  static properties = {
    session: { type: Object },
    sessionKinds: { type: Array },
    labels: { type: Array },
    disabled: { type: Boolean },
    _visibleLabelCount: { state: true },
  };

  constructor() {
    super();
    this.session = {};
    this.sessionKinds = [];
    this.labels = [];
    this.disabled = false;
    this._labelsFitFrame = null;
    this._labelsResizeObserver = null;
    this._labelsRowWidth = 0;
    this._labelsTooltipId = `session-card-labels-tooltip-${++labelsTooltipCount}`;
    this._observedLabelsRow = null;
    this._visibleLabelCount = null;
  }

  connectedCallback() {
    super.connectedCallback();
    // Reattached cards observe and fit their labels row again.
    if (this.hasUpdated) {
      this._visibleLabelCount = null;
      this.requestUpdate();
    }
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    cancelAnimationFrame(this._labelsFitFrame);
    this._labelsFitFrame = null;
    this._labelsResizeObserver?.disconnect();
    this._labelsResizeObserver = null;
    this._observedLabelsRow = null;
  }

  /**
   * Fits the labels row again once web fonts load, since they change the chip widths but not the
   * row width the resize observer watches.
   */
  firstUpdated() {
    document.fonts?.ready.then(() => {
      if (!this.isConnected || this._assignedLabels.length === 0) {
        return;
      }
      this._visibleLabelCount = null;
      this.requestUpdate();
    });
  }

  /**
   * Measures the labels row again when the session or labels change.
   * @param {Map} changedProperties Changed properties.
   */
  willUpdate(changedProperties) {
    if (changedProperties.has("labels") || changedProperties.has("session")) {
      this._visibleLabelCount = null;
    }
  }

  /**
   * Fits the labels row after rendering every chip for measurement.
   */
  updated() {
    this._observeLabelsRow();
    if (this._visibleLabelCount === null) {
      this._fitLabelChips();
    }
  }

  /**
   * Gets the named labels assigned to the session.
   * @returns {Array<{color: string, event_label_id: string, name: string}>}
   * @private
   */
  get _assignedLabels() {
    const labelIds = new Set((this.session?.label_ids || []).map((id) => String(id)));
    return normalizeLabels(this.labels).filter((label) => labelIds.has(label.event_label_id));
  }

  /**
   * Counts the label chips that fit in the labels row.
   * @private
   */
  _fitLabelChips() {
    const row = this.querySelector("[data-session-labels]");
    const availableWidth = row?.clientWidth || 0;
    if (availableWidth === 0) {
      return;
    }

    const chipWidths = Array.from(row.querySelectorAll("[data-session-label]")).map(
      (chip) => chip.getBoundingClientRect().width,
    );
    const gap = parseFloat(getComputedStyle(row).columnGap) || 0;
    // The counter button sets the counter width; its tooltip panel is positioned out of flow.
    const moreTrigger = row.querySelector("[data-session-labels-more] > button");
    const moreWidth = moreTrigger ? moreTrigger.getBoundingClientRect().width + gap : 0;
    this._visibleLabelCount = countFittingChips(chipWidths, availableWidth, gap, moreWidth);
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

  /**
   * Observes the labels row width to fit its chips again after resizing.
   * @private
   */
  _observeLabelsRow() {
    const row = this.querySelector("[data-session-labels]");
    if (row === this._observedLabelsRow || typeof ResizeObserver === "undefined") {
      return;
    }

    this._labelsResizeObserver?.disconnect();
    this._observedLabelsRow = row;
    if (!row) {
      return;
    }

    this._labelsRowWidth = row.clientWidth;
    this._labelsResizeObserver ||= new ResizeObserver(() => {
      const width = this._observedLabelsRow?.clientWidth || 0;
      if (width !== this._labelsRowWidth) {
        this._labelsRowWidth = width;
        // Fit on the next frame to avoid changing layout inside the observer callback.
        cancelAnimationFrame(this._labelsFitFrame);
        this._labelsFitFrame = requestAnimationFrame(() => {
          this._labelsFitFrame = null;
          // A card that was never fitted is already null, so request the measuring render explicitly.
          this._visibleLabelCount = null;
          this.requestUpdate();
        });
      }
    });
    this._labelsResizeObserver.observe(row);
  }

  _onEdit() {
    this.dispatchEvent(new CustomEvent("edit", { bubbles: true, composed: true }));
  }

  _onDelete() {
    this.dispatchEvent(new CustomEvent("delete", { bubbles: true, composed: true }));
  }

  /**
   * Renders the assigned labels in one row, with hidden labels behind a counter.
   * @returns {import("lit").TemplateResult|string}
   * @private
   */
  _renderLabelChips() {
    const labels = this._assignedLabels;
    if (labels.length === 0) return "";

    const isMeasuring = this._visibleLabelCount === null;
    const visibleCount = isMeasuring ? labels.length : Math.min(this._visibleLabelCount, labels.length);
    const hiddenCount = labels.length - visibleCount;
    // While measuring, the counter shows its widest value so the fit reserves enough space.
    const moreCount = isMeasuring ? labels.length : hiddenCount;
    const showMore = isMeasuring ? labels.length > 1 : hiddenCount > 0;
    const allHidden = !isMeasuring && visibleCount === 0;

    return html`
      <div class="mt-1.5 flex h-6 min-w-0 items-center gap-1.5 overflow-x-clip" data-session-labels>
        ${labels
          .slice(0, visibleCount)
          .map(
            (label, index) => html`
              <span
                class="custom-badge inline-block truncate px-2 py-0.5 text-stone-900 ${
                  !isMeasuring && index === 0 ? "min-w-0" : "shrink-0"
                }"
                style=${labelColorStyle(label.color)}
                title=${label.name}
                data-session-label
                >${label.name}</span
              >
            `,
          )}
        ${showMore ? this._renderLabelsMore(moreCount, labels, allHidden) : ""}
      </div>
    `;
  }

  /**
   * Renders the hidden labels counter as a tooltip trigger whose panel lists every label.
   * @param {number} count Number of hidden labels shown in the counter.
   * @param {Array<{color: string, event_label_id: string, name: string}>} labels Assigned labels.
   * @param {boolean} allHidden Whether no chip fits, so the counter shows the labels total.
   * @returns {import("lit").TemplateResult}
   * @private
   */
  _renderLabelsMore(count, labels, allHidden) {
    const plural = count === 1 ? "" : "s";
    // The visible "+N" stays in the accessible name, completed by the sr-only suffix.
    const counterContent = allHidden
      ? `${count} label${plural}`
      : html`+${count}<span class="sr-only"> more label${plural}</span>`;

    return html`
      <span class="group/labels-more relative inline-flex shrink-0" data-session-labels-more>
        <button
          type="button"
          class="relative cursor-help rounded-full border border-stone-200 bg-stone-100 px-2 py-0.5 text-[10px] font-medium text-nowrap text-stone-700 before:absolute before:inset-x-0 before:-inset-y-1 before:content-[''] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-edge"
          aria-describedby=${this._labelsTooltipId}
        >
          ${counterContent}
        </button>
        <span
          id=${this._labelsTooltipId}
          role="tooltip"
          data-tooltip-panel
          class="pointer-events-auto invisible absolute bottom-full start-0 z-20 mb-1 w-64 max-w-[calc(100vw-2rem)] whitespace-normal rounded-lg border border-stone-200 bg-raised p-3 text-start opacity-0 shadow-lg transition-opacity group-hover/labels-more:visible group-hover/labels-more:opacity-100 group-focus-within/labels-more:visible group-focus-within/labels-more:opacity-100"
        >
          <span class="flex flex-wrap gap-1.5">
            ${labels.map(
              (label) => html`
                <span
                  class="inline-block max-w-full truncate rounded-full border px-2 py-0.5 text-[10px] font-medium uppercase text-stone-900"
                  style=${labelColorStyle(label.color)}
                  data-session-label-name
                  >${label.name}</span
                >
              `,
            )}
          </span>
        </span>
      </span>
    `;
  }

  /**
   * Renders speaker avatars with overflow indicator.
   * @returns {import("lit").TemplateResult|string}
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
    // Cards of events with labels keep the height of a card with a labels row.
    const hasEventLabels = normalizeLabels(this.labels).length > 0;

    return html`
      <div
        class="flex w-full min-w-0 items-center gap-4 p-4 border border-stone-200 rounded-lg bg-surface transition-all overflow-hidden ${
          this.disabled ? "" : "hover:border-primary-edge-soft hover:shadow-sm"
        }"
      >
        <div class="flex items-center gap-3 self-stretch shrink-0">
          <div class="text-right w-14">
            <div class="text-sm font-medium text-stone-700">${startTime || "--:--"}</div>
            <div class="text-sm text-stone-400">${endTime || html`&nbsp;`}</div>
          </div>
          <div class="w-0.5 min-h-10 self-stretch bg-primary-edge-soft rounded-full"></div>
        </div>

        <div
          class="flex flex-1 flex-col justify-center w-0 min-w-0 overflow-hidden ${
            hasEventLabels ? "min-h-[4.625rem]" : ""
          }"
          data-session-content
        >
          <div class="flex items-center min-w-0">
            <span class="font-medium text-stone-900 truncate">${session.name || "Untitled Session"}</span>
            ${this._renderSpeakerAvatars()}
          </div>
          <div class="text-sm text-stone-500 truncate w-full">
            ${kindName}${session.location ? html` · ${session.location}` : ""}
          </div>
          ${this._renderLabelChips()}
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

/**
 * Counts how many chips fit before the hidden labels counter.
 * @param {number[]} chipWidths Rendered chip widths, in display order.
 * @param {number} availableWidth Labels row width.
 * @param {number} gap Gap between row items.
 * @param {number} moreWidth Counter width, including its leading gap.
 * @returns {number} Number of visible chips. It may return 0 when the first chip doesn't fit and
 *   the counter leaves less than `MIN_VISIBLE_CHIP_WIDTH` for it; a single chip always stays.
 */
const countFittingChips = (chipWidths, availableWidth, gap, moreWidth) => {
  let usedWidth = 0;
  for (let index = 0; index < chipWidths.length; index += 1) {
    usedWidth += chipWidths[index] + (index > 0 ? gap : 0);
    const reservedWidth = index < chipWidths.length - 1 ? moreWidth : 0;
    if (usedWidth + reservedWidth > availableWidth) {
      if (index > 0) {
        return index;
      }
      // The first chip truncates when the counter leaves it enough room.
      return chipWidths.length === 1 || availableWidth - moreWidth >= MIN_VISIBLE_CHIP_WIDTH ? 1 : 0;
    }
  }
  return chipWidths.length;
};

customElements.define("session-card", SessionCard);
