import { html } from "/static/vendor/js/lit-all.v3.3.3.min.js";
import { ocgFetch } from "/static/js/common/fetch.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { clearTimeoutId, replaceTimeout } from "/static/js/common/timers.js";

const BADGE_LOAD_ERROR_MESSAGE = "We couldn't load the badges. Check your connection and try again.";
const BADGE_SEARCH_DELAY = 300;

const STATE = Object.freeze({
  IDLE: "idle",
  LOADING: "loading",
  EMPTY: "empty",
  READY: "ready",
  SUBMITTING: "submitting",
  SUCCESS: "success",
  ERROR: "error",
});

/** Shared light-DOM dialog for badge awards to explicit recipients. */
export class BadgeAwardModal extends LitWrapper {
  static properties = {
    _allSpeakersAward: { type: Boolean, state: true },
    _badges: { type: Array, state: true },
    _error: { type: String, state: true },
    _isOpen: { type: Boolean, state: true },
    _query: { type: String, state: true },
    _selectedBadgeId: { type: String, state: true },
    _state: { type: String, state: true },
    _success: { type: Object, state: true },
  };

  constructor() {
    super();
    this._allSpeakersAward = false;
    this._badges = [];
    this._error = "";
    this._isOpen = false;
    this._query = "";
    this._selectedBadgeId = "";
    this._state = STATE.IDLE;
    this._success = null;
    this._abortController = null;
    this._awardAbortController = null;
    this._awardRequestId = 0;
    this._eventId = "";
    this._requestId = 0;
    this._returnFocus = null;
    this._searchTimeoutId = 0;
    this._userIds = [];
    this._handleDocumentClick = this._handleDocumentClick.bind(this);
  }

  connectedCallback() {
    super.connectedCallback();
    document.addEventListener("click", this._handleDocumentClick);
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    document.removeEventListener("click", this._handleDocumentClick);
    this._abortController?.abort();
    this._awardAbortController?.abort();
    this._searchTimeoutId = clearTimeoutId(this._searchTimeoutId);
    this.querySelector("[data-badge-award-dialog]")?.close();
    this._isOpen = false;
  }

  _handleDocumentClick(event) {
    const trigger = event.target?.closest?.("[data-badge-award-open]");
    if (!trigger || trigger.disabled) {
      return;
    }
    event.preventDefault();
    const menu = trigger.closest("details[open]");
    const returnFocus = menu?.querySelector("summary") || trigger;
    menu?.removeAttribute("open");
    this.open({
      allSpeakersAward: trigger.hasAttribute("data-badge-award-all-speakers"),
      eventId: trigger.dataset.eventId,
      trigger: returnFocus,
      userIds: (trigger.dataset.userIds || "")
        .split(",")
        .map((userId) => userId.trim())
        .filter(Boolean),
    });
  }

  open({ allSpeakersAward = false, eventId = "", trigger, userIds = [] }) {
    const normalizedUserIds = [...new Set(userIds.filter(Boolean))];
    if (normalizedUserIds.length === 0) {
      return;
    }
    this._abortController?.abort();
    this._awardAbortController?.abort();
    this._searchTimeoutId = clearTimeoutId(this._searchTimeoutId);
    this._awardRequestId += 1;
    this._allSpeakersAward = allSpeakersAward;
    this._eventId = eventId;
    this._userIds = normalizedUserIds;
    this._returnFocus = trigger;
    this._badges = [];
    this._error = "";
    this._query = "";
    this._selectedBadgeId = "";
    this._success = null;
    this._isOpen = true;
    this.updateComplete.then(() => {
      if (this._isOpen) {
        const dialog = this.querySelector("[data-badge-award-dialog]");
        if (!dialog?.open) {
          dialog?.showModal();
        }
        this.querySelector('[aria-label="Close award badge dialog"]')?.focus();
      }
    });
    this._loadBadges();
  }

  close({ restoreFocus = true } = {}) {
    this._abortController?.abort();
    this._awardAbortController?.abort();
    this._searchTimeoutId = clearTimeoutId(this._searchTimeoutId);
    this._awardRequestId += 1;
    this.querySelector("[data-badge-award-dialog]")?.close();
    this._isOpen = false;
    this._state = STATE.IDLE;
    if (restoreFocus) {
      this._returnFocus?.focus?.();
    }
  }

  _cancel(event) {
    event.preventDefault();
    if (this._state === STATE.SUBMITTING) {
      return;
    }
    this.close();
  }

  _dismissFromBackdrop(event) {
    if (event.target === event.currentTarget && this._state !== STATE.SUBMITTING) {
      event.preventDefault();
      this.close();
    }
  }

  async _loadBadges() {
    const requestId = ++this._requestId;
    this._abortController?.abort();
    this._abortController = new AbortController();
    this._badges = [];
    this._selectedBadgeId = "";
    this._state = STATE.LOADING;
    this._error = "";
    try {
      const params = new URLSearchParams();
      if (this._query.trim()) {
        params.set("query", this._query.trim());
      }
      const response = await ocgFetch(`/dashboard/group/badges/options?${params}`, {
        signal: this._abortController.signal,
      });
      if (!response.ok) {
        throw new Error(BADGE_LOAD_ERROR_MESSAGE);
      }
      const output = await response.json();
      if (requestId !== this._requestId) {
        return;
      }
      this._badges = Array.isArray(output.badges) ? output.badges : [];
      this._state = this._badges.length ? STATE.READY : STATE.EMPTY;
      await this.updateComplete;
      this.querySelector("[data-badge-search]")?.focus();
    } catch (error) {
      if (error.name === "AbortError" || requestId !== this._requestId) {
        return;
      }
      this._error = BADGE_LOAD_ERROR_MESSAGE;
      this._state = STATE.ERROR;
      await this.updateComplete;
      if (this._isOpen && requestId === this._requestId) {
        this.querySelector("[data-badge-search]")?.focus();
      }
    }
  }

  /**
   * Clears the badge query and restores the full badge list.
   * @returns {void}
   * @private
   */
  _clearSearch() {
    this._query = "";
    this._searchTimeoutId = clearTimeoutId(this._searchTimeoutId);
    this._loadBadges();
  }

  /**
   * Debounces remote badge filtering while the query changes.
   * @param {InputEvent} event Input event from the badge search field.
   * @returns {void}
   * @private
   */
  _handleSearchInput(event) {
    this._query = event.target.value;
    this._searchTimeoutId = replaceTimeout(
      this._searchTimeoutId,
      () => {
        this._searchTimeoutId = 0;
        this._loadBadges();
      },
      BADGE_SEARCH_DELAY,
    );
  }

  _search(event) {
    event.preventDefault();
    this._searchTimeoutId = clearTimeoutId(this._searchTimeoutId);
    this._loadBadges();
  }

  async _award() {
    if (!this._selectedBadgeId || this._state !== STATE.READY) {
      return;
    }
    const requestId = ++this._awardRequestId;
    this._awardAbortController?.abort();
    this._awardAbortController = new AbortController();
    this._state = STATE.SUBMITTING;
    this._error = "";
    const input = {
      badge_id: this._selectedBadgeId,
      user_ids: this._userIds,
    };
    if (this._eventId) {
      input.event_id = this._eventId;
    }
    try {
      const response = await ocgFetch("/dashboard/group/badges/award", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(input),
        signal: this._awardAbortController.signal,
      });
      if (!response.ok) {
        throw new Error((await response.text()).trim() || "The badge could not be awarded.");
      }
      const success = await response.json();
      if (!this._isOpen || requestId !== this._awardRequestId) {
        return;
      }
      this._success = success;
      this._state = STATE.SUCCESS;
      await this.updateComplete;
      if (this._isOpen && requestId === this._awardRequestId) {
        this.querySelector("[data-badge-award-close]")?.focus();
      }
    } catch (error) {
      if (error.name === "AbortError" || !this._isOpen || requestId !== this._awardRequestId) {
        return;
      }
      this._error = error.message;
      this._state = STATE.READY;
    }
  }

  _renderBadges() {
    if (this._state === STATE.LOADING) {
      return html`<p class="py-8 text-center text-stone-600" role="status">Loading badges…</p>`;
    }
    if (this._state === STATE.EMPTY) {
      return html`<p class="rounded-lg border border-dashed border-stone-300 p-6 text-center text-stone-600">
        No badges matched. Create a badge in the group dashboard or try another search.
      </p>`;
    }
    return html`
      <div class="grid max-h-80 scroll-p-1 gap-3 overflow-y-auto p-1" role="radiogroup" aria-label="Badge">
        ${this._badges.map(
          (badge) => html`
            <label class="relative cursor-pointer">
              <input
                class="peer sr-only"
                type="radio"
                name="award-badge"
                value=${badge.badge_id}
                ?disabled=${this._state !== STATE.READY}
                .checked=${this._selectedBadgeId === badge.badge_id}
                @change=${() => {
                  this._selectedBadgeId = badge.badge_id;
                }}
              />
              <span
                class="grid grid-cols-[3.5rem_1fr] items-center gap-3 rounded-xl border border-stone-200 bg-white p-3 pr-12 transition hover:border-primary-300 hover:shadow-sm peer-checked:border-primary-400 peer-checked:ring-2 peer-checked:ring-primary-200 peer-focus-visible:ring-2 peer-focus-visible:ring-primary-500 peer-focus-visible:ring-offset-2"
              >
                <img
                  class="size-14 rounded-md object-cover"
                  src=${`/images/badges/${badge.image_file_name}`}
                  alt=${`${badge.name} badge artwork`}
                  width="56"
                  height="56"
                />
                <span class="min-w-0">
                  <span class="line-clamp-2 break-words font-semibold text-stone-900">${badge.name}</span>
                </span>
              </span>
              <span
                class="pointer-events-none absolute right-2 top-2 size-6 rounded-full border-2 border-stone-300 bg-white peer-checked:border-primary-500"
                aria-hidden="true"
              ></span>
              <span
                class="pointer-events-none absolute right-3.5 top-3.5 hidden size-3 rounded-full bg-primary-500 peer-checked:block"
                aria-hidden="true"
              ></span>
            </label>
          `,
        )}
      </div>
    `;
  }

  _renderSuccess() {
    const queued = this._success?.queued_count || 0;
    const skipped = this._success?.skipped_count || 0;
    return html`
      <div class="rounded-lg border border-green-200 bg-green-50 p-5" role="status">
        <h4 class="font-semibold text-green-900">Award accepted</h4>
        <p class="mt-1 text-sm text-green-900">
          ${queued} new ${queued === 1 ? "credential" : "credentials"} queued for issuance.
          ${skipped ? `${skipped} active holder${skipped === 1 ? " was" : "s were"} skipped.` : ""}
        </p>
      </div>
    `;
  }

  render() {
    if (!this._isOpen) {
      return html``;
    }
    const busy = this._state === STATE.LOADING || this._state === STATE.SUBMITTING;
    const submitting = this._state === STATE.SUBMITTING;
    return html`
      <dialog
        class="m-auto w-full max-w-2xl overflow-visible bg-transparent p-4 backdrop:bg-stone-950/35"
        data-badge-award-dialog
        aria-labelledby="badge-award-modal-title"
        tabindex="-1"
        @cancel=${this._cancel}
        @click=${this._dismissFromBackdrop}
      >
        <div class="modal-panel w-full max-w-2xl">
          <div class="modal-card rounded-lg">
            <div class="flex items-center justify-between border-b border-stone-200 p-5">
              <h3 id="badge-award-modal-title" class="text-xl font-semibold text-stone-900">Award badge</h3>
              <button
                type="button"
                class="btn-tertiary p-2"
                aria-label="Close award badge dialog"
                ?disabled=${submitting}
                @click=${() => this.close()}
              >
                <span class="svg-icon size-5 icon-close"></span>
              </button>
            </div>
            <div class="modal-body space-y-5 p-5">
              ${
                this._state === STATE.SUCCESS
                  ? this._renderSuccess()
                  : html`
                      ${
                        this._allSpeakersAward
                          ? html`
                              <div
                                class="rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900"
                                data-badge-award-all-speakers-notice
                                role="alert"
                              >
                                <div class="flex items-start gap-2">
                                  <span
                                    class="svg-icon icon-warning mt-0.5 size-4 shrink-0 bg-amber-700"
                                    aria-hidden="true"
                                  ></span>
                                  <span>
                                    This badge will be awarded to all event speakers, including speakers
                                    assigned to individual sessions.
                                  </span>
                                </div>
                              </div>
                            `
                          : ""
                      }
                      <form class="relative" @submit=${(event) => this._search(event)}>
                        <div class="pointer-events-none absolute inset-y-0 start-0 flex items-center ps-3">
                          <span class="svg-icon size-4 icon-search bg-stone-300" aria-hidden="true"></span>
                        </div>
                        <label class="grow">
                          <span class="sr-only">Search badges</span>
                          <input
                            class="input-primary peer w-full ps-9 pe-9"
                            data-badge-search
                            type="search"
                            placeholder="Search badges"
                            autocomplete="off"
                            autocorrect="off"
                            autocapitalize="off"
                            spellcheck="false"
                            ?disabled=${busy}
                            .value=${this._query}
                            @input=${(event) => this._handleSearchInput(event)}
                          />
                        </label>
                        ${
                          this._query
                            ? html`<button
                                class="absolute end-1.5 top-1.5 cursor-pointer"
                                type="button"
                                data-badge-search-clear
                                aria-label="Clear badge search"
                                ?disabled=${busy}
                                @click=${() => this._clearSearch()}
                              >
                                <span
                                  class="svg-icon size-5 icon-close bg-stone-400 hover:bg-stone-700"
                                ></span>
                              </button>`
                            : ""
                        }
                      </form>
                      ${this._renderBadges()}
                      ${
                        this._error
                          ? html`
                              <div
                                class="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-900"
                                role="alert"
                                aria-live="assertive"
                              >
                                <div class="flex items-start gap-2">
                                  <span
                                    class="svg-icon icon-error mt-0.5 size-4 shrink-0"
                                    aria-hidden="true"
                                  ></span>
                                  <span>${this._error}</span>
                                </div>
                              </div>
                            `
                          : ""
                      }
                    `
              }
            </div>
            <div class="flex justify-end gap-3 border-t border-stone-200 p-5">
              <button
                class="btn-primary-outline"
                type="button"
                data-badge-award-close
                ?disabled=${submitting}
                @click=${() => this.close()}
              >
                ${this._state === STATE.SUCCESS ? "Close" : "Cancel"}
              </button>
              ${
                this._state === STATE.SUCCESS
                  ? ""
                  : html`<button
                      class="btn-primary"
                      type="button"
                      ?disabled=${!this._selectedBadgeId || this._state !== STATE.READY}
                      @click=${() => this._award()}
                    >
                      ${submitting ? "Awarding…" : "Award"}
                    </button>`
              }
            </div>
          </div>
        </div>
      </dialog>
    `;
  }
}

customElements.define("badge-award-modal", BadgeAwardModal);
