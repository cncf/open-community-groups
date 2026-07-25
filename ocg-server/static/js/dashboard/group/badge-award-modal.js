import { html } from "/static/vendor/js/lit-all.v3.3.3.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { ocgFetch } from "/static/js/common/fetch.js";

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
    _badges: { type: Array },
    _error: { type: String },
    _isOpen: { type: Boolean },
    _query: { type: String },
    _selectedBadgeId: { type: String },
    _state: { type: String },
    _success: { type: Object },
  };

  constructor() {
    super();
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
    this.querySelector("[data-badge-award-dialog]")?.close();
    this._isOpen = false;
  }

  _handleDocumentClick(event) {
    const trigger = event.target?.closest?.("[data-badge-award-open]");
    if (!trigger || trigger.disabled) {
      return;
    }
    event.preventDefault();
    trigger.closest("details[open]")?.removeAttribute("open");
    this.open({
      eventId: trigger.dataset.eventId,
      trigger,
      userIds: (trigger.dataset.userIds || "")
        .split(",")
        .map((userId) => userId.trim())
        .filter(Boolean),
    });
  }

  open({ eventId = "", trigger, userIds = [] }) {
    const normalizedUserIds = [...new Set(userIds.filter(Boolean))];
    if (normalizedUserIds.length === 0) {
      return;
    }
    this._abortController?.abort();
    this._awardAbortController?.abort();
    this._awardRequestId += 1;
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
        dialog?.focus();
      }
    });
    this._loadBadges();
  }

  close({ restoreFocus = true } = {}) {
    this._abortController?.abort();
    this._awardAbortController?.abort();
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
        throw new Error("Badges could not be loaded.");
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
      this._error = error.message;
      this._state = STATE.ERROR;
    }
  }

  _search(event) {
    event.preventDefault();
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
      this._state = STATE.ERROR;
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
      <div class="grid max-h-80 gap-3 overflow-y-auto" role="radiogroup" aria-label="Badge">
        ${this._badges.map(
          (badge) => html`
            <label
              class="grid cursor-pointer grid-cols-[3.5rem_1fr] gap-3 rounded-lg border p-3 has-[:checked]:border-primary-500 has-[:checked]:bg-primary-50"
            >
              <input
                class="sr-only"
                type="radio"
                name="award-badge"
                value=${badge.badge_id}
                ?disabled=${this._state !== STATE.READY}
                .checked=${this._selectedBadgeId === badge.badge_id}
                @change=${() => {
                  this._selectedBadgeId = badge.badge_id;
                }}
              />
              <img
                class="size-14 rounded-md object-cover"
                src=${`/images/badges/${badge.image_file_name}`}
                alt=${`${badge.name} badge artwork`}
                width="56"
                height="56"
              />
              <span class="min-w-0">
                <span class="block font-semibold text-stone-900">${badge.name}</span>
                <span class="mt-1 block text-sm text-stone-600">${badge.description}</span>
              </span>
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
                      <form class="flex gap-2" @submit=${(event) => this._search(event)}>
                        <label class="grow">
                          <span class="sr-only">Search badges</span>
                          <input
                            class="input-primary"
                            data-badge-search
                            type="search"
                            placeholder="Search badges"
                            ?disabled=${busy}
                            .value=${this._query}
                            @input=${(event) => {
                              this._query = event.target.value;
                            }}
                          />
                        </label>
                        <button class="btn-primary-outline" type="submit" ?disabled=${busy}>Search</button>
                      </form>
                      ${this._renderBadges()}
                      <p class="min-h-5 text-sm text-red-700" role="alert" aria-live="assertive">
                        ${this._error}
                      </p>
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
