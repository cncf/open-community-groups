import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";

/**
 * BreadcrumbNav - Responsive breadcrumb navigation component with optional banner.
 *
 * Attributes:
 * - items: JSON array of breadcrumb items
 *   - label: string (required) - Display text
 *   - href: string (optional) - Link URL (omit for current page)
 *   - icon: string (required) - Icon name without 'icon-' prefix
 *   - current: boolean (optional) - Mark as current page
 * - banner-url: string (optional) - URL to banner image displayed above breadcrumb
 *
 * Example:
 * <breadcrumb-nav
 *   banner-url="/path/to/banner.jpg"
 *   items='[
 *     {"label": "Home", "href": "/", "icon": "home"},
 *     {"label": "Group", "href": "/community/group/slug", "icon": "groups"},
 *     {"label": "Event", "icon": "date", "current": true}
 *   ]'>
 * </breadcrumb-nav>
 */
export class BreadcrumbNav extends LitWrapper {
  static get properties() {
    return {
      items: { type: Array },
      bannerUrl: { type: String, attribute: "banner-url" },
      _isOpen: { type: Boolean, state: true },
    };
  }

  constructor() {
    super();
    this.items = [];
    this.bannerUrl = null;
    this._isOpen = false;
    this._dropdownId = `breadcrumb-dropdown-${Math.random().toString(36).slice(2, 9)}`;
    this._handleDocumentClick = this._handleDocumentClick.bind(this);
    this._handleKeydown = this._handleKeydown.bind(this);
  }

  connectedCallback() {
    super.connectedCallback();

    if (typeof this.items === "string") {
      try {
        this.items = JSON.parse(this.items);
      } catch (_) {
        this.items = [];
      }
    }

    document.addEventListener("click", this._handleDocumentClick);
    document.addEventListener("keydown", this._handleKeydown);
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    document.removeEventListener("click", this._handleDocumentClick);
    document.removeEventListener("keydown", this._handleKeydown);
  }

  willUpdate(changedProperties) {
    if (changedProperties.has("items") && typeof this.items === "string") {
      try {
        this.items = JSON.parse(this.items);
      } catch (_) {
        this.items = [];
      }
    }
  }

  _handleDocumentClick(event) {
    if (!this._isOpen) {
      return;
    }

    const trigger = this.querySelector("[data-breadcrumb-trigger]");
    const dropdown = this.querySelector("[data-breadcrumb-dropdown]");

    if (!trigger || !dropdown) {
      return;
    }

    const clickedTrigger = trigger.contains(event.target);
    const clickedDropdown = dropdown.contains(event.target);

    if (!clickedTrigger && !clickedDropdown) {
      this._isOpen = false;
    }
  }

  _handleKeydown(event) {
    if (event.key === "Escape" && this._isOpen) {
      this._isOpen = false;
      const trigger = this.querySelector("[data-breadcrumb-trigger]");
      if (trigger) {
        trigger.focus();
      }
    }
  }

  _toggleDropdown(event) {
    event.stopPropagation();
    this._isOpen = !this._isOpen;
  }

  _closeDropdown() {
    this._isOpen = false;
  }

  _getCurrentItem() {
    return this.items.find((item) => item.current) || this.items[this.items.length - 1];
  }

  _renderMobileDropdownItem(item) {
    const isCurrent = item.current;

    if (isCurrent || !item.href) {
      return html`
        <div
          class="flex items-center gap-3 px-4 py-2.5 bg-stone-50 text-sm"
          role="option"
          aria-selected="true"
          aria-current="page"
        >
          <span class="shrink-0 text-stone-600">
            <div class="svg-icon size-4 bg-current icon-${item.icon}"></div>
          </span>
          <span class="text-stone-900 font-medium truncate flex-1">${item.label}</span>
        </div>
      `;
    }

    return html`
      <a
        href="${item.href}"
        class="flex items-center gap-3 px-4 py-2.5 hover:bg-stone-50 transition-colors group text-sm"
        role="option"
        aria-selected="false"
        hx-boost="true"
        hx-target="body"
        @click="${this._closeDropdown}"
      >
        <span class="shrink-0 text-stone-400 group-hover:text-stone-600 transition-colors">
          <div class="svg-icon size-4 bg-current icon-${item.icon}"></div>
        </span>
        <span class="text-stone-600 group-hover:text-stone-900 truncate flex-1 transition-colors">
          ${item.label}
        </span>
      </a>
    `;
  }

  _renderDesktopItem(item, index) {
    const isHome = item.icon === "home";
    const isLast = index === this.items.length - 1;
    const isCurrent = item.current || isLast;

    const separator = html`
      <li class="shrink-0" aria-hidden="true">
        <div class="svg-icon size-4 bg-stone-300 icon-arrow-right"></div>
      </li>
    `;

    const content = isCurrent
      ? html`
          <li
            class="flex items-center gap-1.5 ${isHome ? "shrink-0" : "min-w-0 breadcrumb-item"}"
            aria-current="page"
          >
            <div class="svg-icon size-4 bg-stone-700 icon-${item.icon} shrink-0"></div>
            <span class="${isHome ? "" : "truncate min-w-0"} text-stone-700 font-medium">
              ${item.label}
            </span>
          </li>
        `
      : html`
          <li class="flex items-center gap-1.5 ${isHome ? "shrink-0" : "min-w-0 breadcrumb-item"}">
            <a
              href="${item.href}"
              class="flex items-center gap-1.5 hover:text-stone-700 hover:underline min-w-0"
              hx-boost="true"
              hx-target="body"
            >
              <div class="svg-icon size-4 bg-stone-500 icon-${item.icon} shrink-0"></div>
              <span class="${isHome ? "" : "truncate min-w-0"}">${item.label}</span>
            </a>
          </li>
        `;

    return html`${index > 0 ? separator : ""}${content}`;
  }

  render() {
    if (!this.items || this.items.length === 0) {
      return html``;
    }

    const currentItem = this._getCurrentItem();
    const nonHomeItems = this.items.filter((item) => item.icon !== "home");
    const breadcrumbCount = Math.max(nonHomeItems.length, 1);

    return html`
      <div class="container mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 pt-3 sm:pt-8 -mb-2 md:-mb-4">
        <div class="bg-white border border-stone-200 rounded-lg overflow-hidden">
          ${this.bannerUrl
            ? html`
                <div class="h-24 w-full">
                  <img src="${this.bannerUrl}" class="w-full h-full object-cover" alt="Banner" />
                </div>
              `
            : ""}
          <nav class="px-4 sm:px-6 lg:px-8 py-3" aria-label="Breadcrumb">
            <!-- Mobile breadcrumb dropdown -->
            <div class="relative sm:hidden">
              <button
                data-breadcrumb-trigger
                class="flex items-center gap-2 w-full text-sm"
                aria-expanded="${this._isOpen}"
                aria-haspopup="listbox"
                aria-controls="${this._dropdownId}"
                @click="${this._toggleDropdown}"
              >
                <div class="svg-icon size-4 bg-stone-400 icon-tree-list"></div>
                <span class="text-stone-600 truncate flex-1 text-left">${currentItem.label}</span>
                <div
                  class="svg-icon size-3 bg-stone-400 icon-caret-down transition-transform duration-200 motion-reduce:transition-none ${this
                    ._isOpen
                    ? "rotate-180"
                    : ""}"
                ></div>
              </button>
              <div
                id="${this._dropdownId}"
                data-breadcrumb-dropdown
                class="origin-top transition-all duration-150 ease-out motion-reduce:transition-none absolute top-full left-0 mt-3 -mx-4 w-[calc(100%+2rem)] bg-white rounded-xl shadow-lg border border-stone-200 z-50 max-h-64 overflow-y-auto ${this
                  ._isOpen
                  ? "opacity-100 scale-y-100 translate-y-0"
                  : "opacity-0 scale-y-95 -translate-y-1 pointer-events-none"}"
                role="listbox"
              >
                <div class="py-1">${this.items.map((item) => this._renderMobileDropdownItem(item))}</div>
              </div>
            </div>

            <!-- Desktop breadcrumb -->
            <ol
              class="hidden sm:flex sm:items-center gap-2 text-sm text-stone-500"
              style="--breadcrumb-count: ${breadcrumbCount};"
            >
              ${this.items.map((item, index) => this._renderDesktopItem(item, index))}
            </ol>
          </nav>
        </div>
      </div>
    `;
  }
}

customElements.define("breadcrumb-nav", BreadcrumbNav);
