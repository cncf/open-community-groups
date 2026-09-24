import { html } from "lit";
import { repeat } from "lit/directives/repeat.js";
import { ComboboxController } from "/static/js/common/combobox.js";
import { ocgFetch } from "/static/js/common/fetch.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { parseJsonAttribute } from "/static/js/common/utils.js";

const GROUP_OPTIONS_ENDPOINT = "/dashboard/group/events/cohosts/groups";
const STATUS_APPROVED = "approved";
const STATUS_PENDING = "pending";

/**
 * Event co-host selector.
 *
 * Lets organizers choose co-host groups by community, submits the co-host
 * selection only after it changes, and exposes display-only preview context.
 * @extends LitWrapper
 */
export class CohostsSelector extends LitWrapper {
  static properties = {
    communities: { type: Array },
    currentGroupId: { type: String, attribute: "current-group-id" },
    disabled: { type: Boolean },
    revision: { type: Number },
    selectedCohosts: { type: Array, attribute: "selected-cohosts" },
    _groups: { state: true },
    _loadStatus: { state: true },
    _selectedCommunityId: { state: true },
  };

  constructor() {
    super();
    this.communities = [];
    this.currentGroupId = "";
    this.disabled = false;
    this.revision = 0;
    this.selectedCohosts = [];
    this._abortController = null;
    this._groups = [];
    this._loadError = "";
    this._loadedGroupIds = [];
    this._loadSequence = 0;
    this._loadStatus = "idle";
    this._selectedCommunityId = "";
    this._combobox = new ComboboxController(this, {
      getItemCount: () => this._filteredGroups.length,
      isInteractionBlocked: () => this.disabled || this._loadStatus === "loading",
      canOpen: () => this._selectedCommunityId && this._groups.length > 0,
      onSelect: (index) => {
        const group = this._filteredGroups[index];
        if (group) {
          this._selectGroup(group);
        }
      },
    });
  }

  connectedCallback() {
    this.communities = normalizeArrayAttribute(this.communities);
    this.selectedCohosts = normalizeArrayAttribute(this.selectedCohosts).map(normalizeSelectedCohost);
    this.revision = Number.parseInt(this.revision, 10) || 0;
    this._loadedGroupIds = this.selectedCohosts.map((cohost) => cohost.group_id);
    this._selectedCommunityId = this.communities[0]?.community_id || "";
    super.connectedCallback();
  }

  disconnectedCallback() {
    this._abortController?.abort();
    super.disconnectedCallback();
  }

  /**
   * Returns display-only co-host data for the event preview.
   * @returns {{name: string, logo_url: string, status: string}[]}
   */
  getPreviewCohosts() {
    return this.selectedCohosts
      .map((cohost) => ({
        logo_url: cohost.logo_url || "",
        name: cohost.name || "",
        status: cohost.status === STATUS_APPROVED ? STATUS_APPROVED : STATUS_PENDING,
      }))
      .filter((cohost) => cohost.name);
  }

  /**
   * Available groups matching the current search and selection.
   * @returns {Array<object>}
   */
  get _filteredGroups() {
    const query = (this._combobox.query || "").trim().toLowerCase();
    const selectedIds = new Set(this.selectedCohosts.map((cohost) => cohost.group_id));
    return this._groups.filter((group) => {
      if (String(group.group_id) === String(this.currentGroupId) || selectedIds.has(group.group_id)) {
        return false;
      }
      if (!query) {
        return true;
      }
      return [group.name, group.community_display_name, group.slug_pretty, group.slug]
        .filter(Boolean)
        .some((value) => String(value).toLowerCase().includes(query));
    });
  }

  /**
   * Whether the current selection differs from the loaded editor state.
   * @returns {boolean}
   */
  get _hasChanged() {
    const currentIds = this.selectedCohosts.map((cohost) => cohost.group_id);
    return !arraysEqual(currentIds, this._loadedGroupIds);
  }

  render() {
    return html`
      <div class="space-y-5">
        ${this._renderCommunityPicker()} ${this._renderGroupPicker()} ${this._renderLoadState()}
        ${this._renderSelectedCohosts()} ${this._renderHiddenFields()}
      </div>
    `;
  }

  _dispatchSelectionChange() {
    this.dispatchEvent(new Event("input", { bubbles: true }));
    this.dispatchEvent(new Event("change", { bubbles: true }));
  }

  async _loadGroups() {
    if (!this._selectedCommunityId || this.disabled) {
      return;
    }

    const sequence = this._loadSequence + 1;
    this._loadSequence = sequence;
    this._abortController?.abort();
    this._abortController = new AbortController();
    this._loadError = "";
    this._loadStatus = "loading";

    try {
      const url = new URL(GROUP_OPTIONS_ENDPOINT, window.location.origin);
      url.searchParams.set("community_id", this._selectedCommunityId);
      const response = await ocgFetch(`${url.pathname}${url.search}`, {
        credentials: "same-origin",
        signal: this._abortController.signal,
      });

      if (!response.ok) {
        throw new Error(`Failed to load co-host groups: ${response.status}`);
      }

      const groups = await response.json();
      if (sequence !== this._loadSequence || !this.isConnected) {
        return;
      }

      this._groups = Array.isArray(groups) ? groups : [];
      this._loadStatus = "ready";
    } catch (error) {
      if (error?.name === "AbortError" || sequence !== this._loadSequence || !this.isConnected) {
        return;
      }
      this._groups = [];
      this._loadError = "Co-host groups could not be loaded. Keep your current selection or try again.";
      this._loadStatus = "error";
    }
  }

  _removeGroup(groupId) {
    if (this.disabled) {
      return;
    }
    this.selectedCohosts = this.selectedCohosts.filter((cohost) => cohost.group_id !== groupId);
    this._dispatchSelectionChange();
  }

  _renderCommunityPicker() {
    return html`
      <div class="max-w-xl">
        <label for="cohost-community" class="form-label">Community</label>
        <select
          id="cohost-community"
          class="select-primary mt-2"
          ?disabled=${this.disabled || this.communities.length === 0}
          .value=${this._selectedCommunityId}
          @change=${(event) => this._selectCommunity(event.target.value)}
        >
          ${this.communities.map(
            (community) =>
              html`<option value=${community.community_id}>
                ${community.display_name || community.name}
              </option>`,
          )}
        </select>
        <p class="form-legend">Choose a community, then search for a group to invite.</p>
      </div>
    `;
  }

  _renderGroupPicker() {
    const isLoading = this._loadStatus === "loading";
    return html`
      <div class="relative max-w-xl">
        <label for="cohost-group-search" class="form-label">Co-host group</label>
        <div class="relative mt-2">
          <div class="absolute top-3 start-0 flex items-center ps-3 pointer-events-none">
            <div class="svg-icon size-4 icon-search bg-stone-300"></div>
          </div>
          <input
            id="cohost-group-search"
            type="search"
            class="input-primary ps-9"
            placeholder=${isLoading ? "Loading groups..." : "Search groups"}
            autocomplete="off"
            autocorrect="off"
            autocapitalize="off"
            spellcheck="false"
            .value=${this._combobox.query}
            ?disabled=${this.disabled || !this._selectedCommunityId || isLoading}
            aria-controls="cohost-group-options"
            aria-expanded=${this._combobox.isOpen ? "true" : "false"}
            @focus=${() => {
              if (this._loadStatus === "idle") {
                this._loadGroups();
              }
              this._combobox.open();
            }}
            @input=${(event) => {
              this._combobox.setQuery(event.target.value || "");
              this._combobox.open();
            }}
          />
        </div>

        <div
          class="absolute start-0 end-0 z-10 mt-1 rounded-lg border border-stone-200 bg-white shadow ${
            this._combobox.isOpen ? "" : "hidden"
          }"
        >
          ${
            this._filteredGroups.length > 0
              ? html`
                  <ul id="cohost-group-options" class="max-h-72 overflow-auto py-1" role="listbox">
                    ${repeat(
                      this._filteredGroups,
                      (group) => group.group_id,
                      (group, index) => this._renderOption(group, index),
                    )}
                  </ul>
                `
              : html`<div class="px-4 py-3 text-sm text-stone-500">
                  ${this._selectedCommunityId ? "No groups found" : "Choose a community first"}
                </div>`
          }
        </div>
      </div>
    `;
  }

  _renderHiddenFields() {
    if (!this._hasChanged) {
      return "";
    }

    return html`
      ${this.selectedCohosts.map(
        (cohost, index) => html`
          <input type="hidden" name="cohost_group_ids[${index}]" value=${cohost.group_id} />
        `,
      )}
      <input type="hidden" name="cohost_group_ids_present" value="true" />
      <input type="hidden" name="cohosts_revision" value=${String(this.revision)} />
    `;
  }

  _renderLoadState() {
    if (this._loadStatus === "loading") {
      return html`<p class="text-sm text-stone-500" role="status">Loading co-host groups...</p>`;
    }

    if (this._loadStatus !== "error") {
      return "";
    }

    return html`
      <div class="max-w-xl rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm/6 text-amber-900">
        <p>${this._loadError}</p>
        <button type="button" class="btn-primary-outline btn-mini mt-3" @click=${() => this._loadGroups()}>
          Retry
        </button>
      </div>
    `;
  }

  _renderOption(group, index) {
    const isActive = this._combobox.activeIndex === index;
    return html`
      <li role="presentation">
        <button
          type="button"
          role="option"
          class="flex w-full items-center gap-3 px-4 py-2 text-left text-sm ${
            isActive ? "bg-stone-50 text-stone-900" : "text-stone-700 hover:bg-stone-50 hover:text-stone-900"
          }"
          @click=${() => this._selectGroup(group)}
          @mouseover=${() => this._combobox.setActiveIndex(index)}
        >
          ${this._renderLogo(group, "size-9", "size-7")}
          <span class="min-w-0">
            <span class="block truncate font-medium">${group.name}</span>
            <span class="block truncate text-xs text-stone-500">${group.community_display_name}</span>
          </span>
        </button>
      </li>
    `;
  }

  _renderSelectedCohosts() {
    if (this.selectedCohosts.length === 0) {
      return html`
        <div class="max-w-xl rounded-lg border border-dashed border-stone-200 p-4 text-sm text-stone-500">
          No co-hosts selected.
        </div>
      `;
    }

    return html`
      <div class="grid grid-cols-1 gap-4 xl:grid-cols-2 2xl:grid-cols-3">
        ${this.selectedCohosts.map(
          (cohost) => html`
            <div class="flex min-w-0 items-center gap-3 rounded-xl border border-stone-200 bg-white p-4">
              ${this._renderLogo(cohost, "size-15 md:size-18", "size-13 md:size-16")}
              <div class="min-w-0 flex-1">
                <div class="truncate text-sm font-semibold text-stone-900 md:text-base">${cohost.name}</div>
                <div class="mt-1 truncate text-xs text-stone-500">${cohost.community_display_name}</div>
                <div class="mt-2 flex flex-wrap gap-1.5">${this._renderStatusPills(cohost)}</div>
              </div>
              ${
                this.disabled
                  ? ""
                  : html`
                      <button
                        type="button"
                        class="rounded-full p-1 hover:bg-stone-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500"
                        aria-label="Remove ${cohost.name}"
                        title="Remove"
                        @click=${() => this._removeGroup(cohost.group_id)}
                      >
                        <span class="svg-icon block size-4 icon-close bg-stone-600" aria-hidden="true"></span>
                      </button>
                    `
              }
            </div>
          `,
        )}
      </div>
    `;
  }

  _renderLogo(group, wrapperSize, imageSize) {
    return html`
      <div
        class="relative flex ${wrapperSize} shrink-0 items-center justify-center overflow-hidden rounded-lg border border-stone-200 bg-white"
      >
        ${
          group.logo_url
            ? html`<img
                src=${group.logo_url}
                alt="${group.name} logo"
                class="${imageSize} object-contain"
                loading="lazy"
              />`
            : html`<span class="svg-icon size-6 icon-groups bg-stone-400" aria-hidden="true"></span>`
        }
      </div>
    `;
  }

  _renderStatusPills(cohost) {
    const statusLabel = cohost.status === STATUS_APPROVED ? "Approved" : "Pending";
    const statusClass =
      cohost.status === STATUS_APPROVED
        ? "border-primary-700 bg-primary-50 text-primary-700"
        : "border-amber-700 bg-amber-50 text-amber-800";

    return html`
      <span class="custom-badge px-2.5 py-0.5 ${statusClass}">${statusLabel}</span>
      ${
        cohost.group_active === false
          ? html`<span class="custom-badge border-stone-500 bg-stone-100 px-2.5 py-0.5 text-stone-700">
              Inactive group
            </span>`
          : ""
      }
    `;
  }

  _selectCommunity(communityId) {
    this._selectedCommunityId = communityId || "";
    this._groups = [];
    this._loadStatus = this._selectedCommunityId ? "idle" : "ready";
    this._combobox.close();
    this._loadGroups();
  }

  _selectGroup(group) {
    if (this.disabled || !group?.group_id) {
      return;
    }
    if (String(group.group_id) === String(this.currentGroupId)) {
      return;
    }
    if (this.selectedCohosts.some((cohost) => cohost.group_id === group.group_id)) {
      return;
    }

    this.selectedCohosts = [
      ...this.selectedCohosts,
      normalizeSelectedCohost({
        ...group,
        group_active: true,
        status: STATUS_PENDING,
      }),
    ];
    this._combobox.close();
    this._dispatchSelectionChange();
  }
}

const arraysEqual = (left, right) =>
  left.length === right.length && left.every((value, index) => value === right[index]);

const normalizeArrayAttribute = (value) => {
  const parsed = parseJsonAttribute(value, []);
  return Array.isArray(parsed) ? parsed : [];
};

const normalizeSelectedCohost = (cohost) => ({
  community_display_name: cohost?.community_display_name || "",
  community_name: cohost?.community_name || "",
  group_active: cohost?.group_active !== false,
  group_id: String(cohost?.group_id || ""),
  invitation_id: cohost?.invitation_id || "",
  invited_at: cohost?.invited_at || "",
  logo_url: cohost?.logo_url || "",
  name: cohost?.name || "",
  slug: cohost?.slug || "",
  slug_pretty: cohost?.slug_pretty || "",
  status: cohost?.status === STATUS_APPROVED ? STATUS_APPROVED : STATUS_PENDING,
});

customElements.define("cohosts-selector", CohostsSelector);
