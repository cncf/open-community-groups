import { html, repeat } from "/static/vendor/js/lit-all.v3.2.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";

/**
 * GroupSelector renders a searchable dropdown to pick a single group.
 *
 * Keyboard interactions follow the ARIA combobox pattern. Down, Up, Home and
 * End move the highlight, Enter selects the highlighted item and Escape closes
 * the menu. Typing in the search field filters results with a debounce to
 * reduce re-render pressure while the user is typing.
 *
 * @property {Array<object>} groups List of groups with group_id and name keys
 * @property {string} selectedGroupId Currently selected group identifier
 * @property {number} searchDelay Debounced search delay in milliseconds
 */
export class GroupSelector extends LitWrapper {
  static properties = {
    groups: {
      attribute: "groups",
      converter: {
        /**
         * Parses the JSON encoded groups list passed through the attribute.
         * @param {string} value Attribute value from the DOM
         * @returns {Array<object>} Parsed collection or empty array on failure
         */
        fromAttribute(value) {
          if (!value) return [];
          try {
            return JSON.parse(value);
          } catch (err) {
            console.error("Invalid groups data", err);
            return [];
          }
        },
      },
    },
    selectedGroupId: { type: String, attribute: "selected-group-id" },
    searchDelay: { type: Number, attribute: "search-delay" },
    _isOpen: { state: true },
    _query: { state: true },
    _filteredGroups: { state: true },
    _highlightIndex: { state: true },
  };

  constructor() {
    super();
    this.groups = [];
    this.selectedGroupId = "";
    this.searchDelay = 250;
    this._isOpen = false;
    this._query = "";
    this._filteredGroups = [];
    this._highlightIndex = -1;
    this._searchTimeoutId = 0;
    this._documentClickHandler = null;
    this._boundHandleKeydown = this._handleKeydown.bind(this);
  }

  connectedCallback() {
    super.connectedCallback();
    this.addEventListener("keydown", this._boundHandleKeydown);
    if (this._filteredGroups.length === 0 && this.groups.length > 0) {
      this._filteredGroups = [...this.groups];
    }
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    this.removeEventListener("keydown", this._boundHandleKeydown);
    this._removeDocumentListener();
    if (this._searchTimeoutId) {
      window.clearTimeout(this._searchTimeoutId);
      this._searchTimeoutId = 0;
    }
  }

  /**
   * Keeps internal collections aligned with external props.
   * @param {Map<string, unknown>} changedProps Changed reactive properties
   */
  willUpdate(changedProps) {
    if (changedProps.has("groups")) {
      this._filteredGroups = Array.isArray(this.groups) ? [...this.groups] : [];
      this._highlightIndex = -1;
    }
    if (changedProps.has("selectedGroupId") && this._isOpen) {
      this._syncHighlightWithSelection();
    }
  }

  /**
   * Processes HTMX hooks when dropdown content changes in the light DOM.
   * @param {Map<string, unknown>} changedProps Changed reactive properties
   */
  updated(changedProps) {
    if (
      (changedProps.has("_filteredGroups") || changedProps.has("_isOpen")) &&
      typeof window !== "undefined" &&
      window.htmx &&
      typeof window.htmx.process === "function"
    ) {
      this.updateComplete.then(() => {
        const buttons = this.querySelectorAll(".group-button");
        if (buttons.length === 0) {
          window.htmx.process(this);
          return;
        }
        buttons.forEach((button) => {
          button.removeAttribute("hx-processed");
          window.htmx.process(button);
        });
      });
    }
  }

  /**
   * Stores the current query and triggers the debounced filtering.
   * @param {InputEvent} event Native input event
   */
  _handleSearchInput(event) {
    const value = event.target.value || "";
    this._query = value;
    if (this._searchTimeoutId) {
      window.clearTimeout(this._searchTimeoutId);
    }
    this._searchTimeoutId = window.setTimeout(() => {
      this._applyFilter();
    }, this.searchDelay);
  }

  /**
   * Applies the current query to the groups collection.
   */
  _applyFilter() {
    const normalized = (this._query || "").trim().toLowerCase();
    if (!normalized) {
      this._filteredGroups = [...this.groups];
    } else {
      this._filteredGroups = this.groups.filter((group) => {
        return (group.name || "").toLowerCase().includes(normalized);
      });
    }
    this._syncHighlightWithSelection();
  }

  /**
   * Handles clicks on a group option and closes the dropdown when needed.
   * @param {MouseEvent} event Option click event
   * @param {object} group Associated group data
   */
  _handleGroupClick(event, group) {
    if (this._isSelected(group)) {
      event.preventDefault();
      event.stopPropagation();
      return;
    }
    this._closeDropdown({ focusButton: true });
  }

  /**
   * Toggles dropdown visibility.
   */
  _toggleDropdown() {
    if (this._isOpen) {
      this._closeDropdown({ focusButton: false });
    } else {
      this._openDropdown();
    }
  }

  /**
   * Opens the dropdown, resets search and attaches outside click handler.
   */
  _openDropdown() {
    if (this.groups.length === 0) {
      return;
    }
    this._isOpen = true;
    this._query = "";
    this._filteredGroups = [...this.groups];
    this._syncHighlightWithSelection();
    this._addDocumentListener();
    this.updateComplete.then(() => {
      const input = this.querySelector("#group-search-input");
      if (input) {
        input.focus();
        input.select();
      }
    });
  }

  /**
   * Closes the dropdown, clears search state and optionally refocuses button.
   * @param {{focusButton: boolean}} options Behavior tweak flags
   */
  _closeDropdown({ focusButton }) {
    this._isOpen = false;
    this._query = "";
    this._filteredGroups = [...this.groups];
    this._highlightIndex = -1;
    this._removeDocumentListener();
    if (focusButton) {
      this.updateComplete.then(() => {
        const btn = this.querySelector("#group-selector-button");
        if (btn) {
          btn.focus();
        }
      });
    }
  }

  /**
   * Registers a click listener on document to detect outside clicks.
   */
  _addDocumentListener() {
    if (this._documentClickHandler) {
      return;
    }
    this._documentClickHandler = (event) => {
      if (!this.contains(event.target)) {
        this._closeDropdown({ focusButton: false });
      }
    };
    document.addEventListener("click", this._documentClickHandler);
  }

  /**
   * Removes the outside click listener if it exists.
   */
  _removeDocumentListener() {
    if (!this._documentClickHandler) {
      return;
    }
    document.removeEventListener("click", this._documentClickHandler);
    this._documentClickHandler = null;
  }

  /**
   * Handles keyboard shortcuts for toggling, navigating and selecting.
   * @param {KeyboardEvent} event Native keyboard event
   */
  _handleKeydown(event) {
    if (event.defaultPrevented) {
      return;
    }

    if (!this._isOpen) {
      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault();
        this._openDropdown();
        this._changeHighlight(event.key === "ArrowDown" ? 1 : -1);
      } else if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        this._toggleDropdown();
      } else if (event.key === "Escape") {
        event.preventDefault();
        this._closeDropdown({ focusButton: true });
      }
      return;
    }

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault();
        this._changeHighlight(1);
        break;
      case "ArrowUp":
        event.preventDefault();
        this._changeHighlight(-1);
        break;
      case "Home":
        event.preventDefault();
        this._jumpToEdge(0);
        break;
      case "End":
        event.preventDefault();
        this._jumpToEdge(this._filteredGroups.length - 1);
        break;
      case "Enter":
        event.preventDefault();
        this._activateHighlight();
        break;
      case "Escape":
        event.preventDefault();
        this._closeDropdown({ focusButton: true });
        break;
      default:
        break;
    }
  }

  /**
   * Updates highlight index based on keyboard navigation.
   * @param {number} step Direction to move the highlight (positive or negative)
   */
  _changeHighlight(step) {
    const total = this._filteredGroups.length;
    if (!total) {
      this._highlightIndex = -1;
      return;
    }
    if (this._highlightIndex === -1) {
      this._highlightIndex = step > 0 ? 0 : total - 1;
    } else {
      this._highlightIndex = (this._highlightIndex + step + total) % total;
    }
    this.updateComplete.then(() => this._scrollHighlightedIntoView());
  }

  /**
   * Moves highlight to an absolute index when Home/End is pressed.
   * @param {number} index Target index within filtered results
   */
  _jumpToEdge(index) {
    if (!this._filteredGroups.length) {
      this._highlightIndex = -1;
      return;
    }
    const bounded = Math.min(Math.max(index, 0), this._filteredGroups.length - 1);
    this._highlightIndex = bounded;
    this.updateComplete.then(() => this._scrollHighlightedIntoView());
  }

  /**
   * Handles activation of the highlighted item via keyboard.
   */
  _activateHighlight() {
    if (this._highlightIndex < 0 || this._highlightIndex >= this._filteredGroups.length) {
      return;
    }
    const group = this._filteredGroups[this._highlightIndex];
    if (!group || this._isSelected(group)) {
      return;
    }
    const button = this.querySelector(`button[data-group-id="${group.group_id}"]`);
    if (button) {
      button.click();
    }
  }

  /**
   * Sets the highlight index when hovering or focusing via pointer.
   * @param {number} index Candidate index
   */
  _setHighlight(index) {
    if (index == null || index < 0 || index >= this._filteredGroups.length) {
      return;
    }
    if (this._highlightIndex === index) {
      return;
    }
    this._highlightIndex = index;
    this.updateComplete.then(() => this._scrollHighlightedIntoView());
  }

  /**
   * Keeps the highlighted item within the scrollable viewport.
   */
  _scrollHighlightedIntoView() {
    if (this._highlightIndex < 0) {
      return;
    }
    const list = this.querySelector("#group-selector-list");
    if (!list) {
      return;
    }
    const item = list.querySelector(`li[data-index="${this._highlightIndex}"]`);
    if (item && typeof item.scrollIntoView === "function") {
      item.scrollIntoView({ block: "nearest" });
    }
  }

  /**
   * Resets highlight to the first option that is not already selected.
   */
  _syncHighlightWithSelection() {
    const firstAvailable = this._filteredGroups.findIndex((group) => !this._isSelected(group));
    this._highlightIndex = firstAvailable >= 0 ? firstAvailable : -1;
  }

  /**
   * Returns the selected group object, or null when none is selected.
   * @returns {object|null}
   */
  _findSelectedGroup() {
    if (!this.groups || this.groups.length === 0) {
      return null;
    }
    const targetId = this.selectedGroupId != null ? String(this.selectedGroupId) : "";
    return this.groups.find((group) => String(group.group_id) === targetId) || null;
  }

  /**
   * Checks whether the provided group matches the selected identifier.
   * @param {object} group Group metadata
   * @returns {boolean}
   */
  _isSelected(group) {
    return String(group.group_id) === String(this.selectedGroupId || "");
  }

  /**
   * Returns the id used for aria-activedescendant referencing the highlight.
   * @returns {string}
   */
  _activeDescendantId() {
    if (this._highlightIndex < 0 || this._highlightIndex >= this._filteredGroups.length) {
      return "";
    }
    const group = this._filteredGroups[this._highlightIndex];
    if (!group) {
      return "";
    }
    return `group-option-${group.group_id}`;
  }

  render() {
    const selectedGroup = this._findSelectedGroup();
    const isDisabled = this.groups.length === 0;

    return html`
      <div class="relative">
        <button
          id="group-selector-button"
          type="button"
          class="cursor-pointer select select-primary relative text-left pe-9 ${isDisabled
            ? "opacity-60 cursor-not-allowed"
            : ""}"
          ?disabled="${isDisabled}"
          aria-haspopup="listbox"
          aria-expanded="${this._isOpen ? "true" : "false"}"
          @click="${() => this._toggleDropdown()}"
        >
          <div class="flex flex-col justify-center min-h-[40px] whitespace-normal leading-tight">
            <div class="text-sm font-medium text-stone-900 whitespace-normal leading-tight">
              ${selectedGroup ? selectedGroup.name : "Select a group"}
            </div>
          </div>
          <div class="absolute inset-y-0 end-0 flex items-center pe-3 pointer-events-none">
            <div class="svg-icon size-3 icon-caret-down bg-stone-600"></div>
          </div>
        </button>

        <div
          class="absolute top-14 left-0 right-0 z-10 bg-white rounded-lg shadow-sm border border-stone-200 ${this
            ._isOpen
            ? ""
            : "hidden"}"
        >
          ${this._renderSearchInput()}
          ${this._filteredGroups.length > 0 ? this._renderResultsList() : this._renderEmptyState()}
        </div>
      </div>
    `;
  }

  /**
   * Renders the search input that powers the filtering behavior.
   * @returns {import("lit").TemplateResult}
   */
  _renderSearchInput() {
    return html`
      <div class="p-3 border-b border-stone-200">
        <div class="relative">
          <div class="absolute top-3 start-0 flex items-center ps-3 pointer-events-none">
            <div class="svg-icon size-4 icon-search bg-stone-300"></div>
          </div>
          <input
            id="group-search-input"
            type="search"
            class="input-primary w-full ps-9"
            placeholder="Search groups"
            autocomplete="off"
            autocorrect="off"
            autocapitalize="off"
            spellcheck="false"
            .value="${this._query}"
            @input="${(event) => this._handleSearchInput(event)}"
          />
        </div>
      </div>
    `;
  }

  /**
   * Renders the listbox with the current filtered groups.
   * @returns {import("lit").TemplateResult}
   */
  _renderResultsList() {
    return html`
      <ul
        id="group-selector-list"
        class="max-h-48 overflow-y-auto text-stone-700"
        role="listbox"
        aria-activedescendant="${this._activeDescendantId()}"
      >
        ${repeat(
          this._filteredGroups,
          (group) => group.group_id,
          (group, index) => this._renderGroupItem(group, index),
        )}
      </ul>
    `;
  }

  /**
   * Renders the button element for an individual group option.
   * @param {object} group Group object containing group_id and name
   * @param {number} index Index used for highlighting
   * @returns {import("lit").TemplateResult}
   */
  _renderGroupItem(group, index) {
    const isSelected = this._isSelected(group);
    const isHighlighted = index === this._highlightIndex;
    const backgroundClass = (() => {
      if (isSelected && isHighlighted) return "bg-stone-200";
      if (isSelected) return "bg-stone-100";
      if (isHighlighted) return "bg-stone-50";
      return "";
    })();

    return html`
      <li role="presentation" data-index="${index}">
        <button
          id="group-option-${group.group_id}"
          type="button"
          class="group-button w-full px-4 py-2 text-sm/6 whitespace-normal leading-tight min-h-[40px] flex flex-col justify-center text-left focus:outline-none ${isSelected
            ? "opacity-50 cursor-not-allowed"
            : "cursor-pointer hover:bg-stone-50"} ${backgroundClass}"
          role="option"
          data-group-id="${group.group_id}"
          ?disabled="${isSelected}"
          hx-put="/dashboard/group/${group.group_id}/select"
          hx-trigger="click"
          hx-target="#dashboard-content"
          hx-indicator="#dashboard-spinner"
          hx-disabled-elt=".group-button"
          @click="${(event) => this._handleGroupClick(event, group)}"
          @mouseenter="${() => this._setHighlight(index)}"
          @focus="${() => this._setHighlight(index)}"
        >
          <div class="text-sm font-medium text-stone-900 whitespace-normal leading-tight">${group.name}</div>
        </button>
      </li>
    `;
  }

  /**
   * Provides feedback when no group matches the search query.
   * @returns {import("lit").TemplateResult}
   */
  _renderEmptyState() {
    return html` <div class="px-4 py-3 text-sm text-stone-500">No groups found.</div> `;
  }
}

customElements.define("group-selector", GroupSelector);
