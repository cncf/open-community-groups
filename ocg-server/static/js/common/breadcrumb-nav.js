import { html, nothing } from "lit";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { isPhoneViewport } from "/static/js/common/phone-viewport.js";
import { parseJsonAttribute } from "/static/js/common/utils.js";

// Natural sizes of the desktop and mobile banners. As the image width and height they hold the
// banner's place until it loads, and as a ratio they shape the load error placeholder.
const DESKTOP_BANNER_SIZE = Object.freeze({ height: 192, width: 2428 });
const MOBILE_BANNER_SIZE = Object.freeze({ height: 192, width: 1220 });

/**
 * BreadcrumbNav - Responsive breadcrumb navigation component with optional banner.
 *
 * Attributes:
 * - items: JSON array of breadcrumb items
 *   - label: string (required) - Display text
 *   - href: string (optional) - Link URL (omit for current page)
 *   - icon: string (required) - Icon name without 'icon-' prefix
 *   - current: boolean (optional) - Mark as current page
 * - banner-url: string (optional) - URL to banner image displayed above breadcrumb (sm+, not phones)
 * - banner-mobile-url: string (optional) - URL to mobile banner image (below sm, and on phones)
 * - banner-dark-url: string (optional) - Dark mode variant of banner-url, ignored without it
 * - banner-mobile-dark-url: string (optional) - Dark mode variant of banner-mobile-url, ignored without it
 * - full-bleed: boolean (optional) - Spans the viewport edge to edge on phones, square and without side borders
 *
 * Example:
 * <breadcrumb-nav
 *   banner-url="/path/to/banner.jpg"
 *   banner-mobile-url="/path/to/banner-mobile.jpg"
 *   banner-dark-url="/path/to/banner-dark.jpg"
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
      bannerMobileUrl: { type: String, attribute: "banner-mobile-url" },
      bannerDarkUrl: { type: String, attribute: "banner-dark-url" },
      bannerMobileDarkUrl: { type: String, attribute: "banner-mobile-dark-url" },
      fullBleed: { type: Boolean, attribute: "full-bleed" },
      _isOpen: { type: Boolean, state: true },
    };
  }

  constructor() {
    super();
    this.items = [];
    this.bannerUrl = null;
    this.bannerMobileUrl = null;
    this.bannerDarkUrl = null;
    this.bannerMobileDarkUrl = null;
    this.fullBleed = false;
    this._isOpen = false;
    this._dropdownId = `breadcrumb-dropdown-${Math.random().toString(36).slice(2, 9)}`;
    this._handleDocumentClick = this._handleDocumentClick.bind(this);
    this._handleKeydown = this._handleKeydown.bind(this);
  }

  connectedCallback() {
    super.connectedCallback();

    this.items = parseJsonAttribute(this.items, []);

    document.addEventListener("click", this._handleDocumentClick);
    document.addEventListener("keydown", this._handleKeydown);
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    document.removeEventListener("click", this._handleDocumentClick);
    document.removeEventListener("keydown", this._handleKeydown);
  }

  willUpdate(changedProperties) {
    if (changedProperties.has("items")) {
      this.items = parseJsonAttribute(this.items, []);
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
    if (isEscapeEvent(event) && this._isOpen) {
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

  /**
   * Replaces a banner whose image fails to load with a neutral placeholder of
   * the same aspect ratio, so the card keeps a consistent banner height instead
   * of showing a broken image. Applies to both the mobile and desktop banners.
   * @param {Event} event - The image error event
   */
  _handleBannerError(event) {
    const img = event.target;
    const banner = img.parentElement;
    if (!banner) {
      return;
    }
    img.style.display = "none";
    if (banner.dataset.bannerAspect) {
      banner.style.aspectRatio = banner.dataset.bannerAspect;
    }
    banner.style.background = "linear-gradient(135deg, var(--color-stone-100), var(--color-stone-200))";
  }

  /**
   * Renders the banner image of one breakpoint. With a dark mode variant, each image gets its
   * own data-theme-image wrapper, so CSS shows the one matching the theme and a load error
   * styles only the failed image's wrapper. The dark image is lazy, so it loads only once shown.
   * Every image carries the banner's natural width and height, so the browser keeps its place
   * before it loads and the breadcrumb below does not jump; a loaded image keeps its own ratio.
   * @param {string} url - Light banner URL
   * @param {string|null} darkUrl - Dark mode banner URL
   * @param {{height: number, width: number}} size - Natural banner size
   * @returns {TemplateResult} Banner image template
   * @private
   */
  _renderBannerImages(url, darkUrl, size) {
    const aspect = getBannerAspect(size);

    if (!darkUrl) {
      return html`
        <img
          src="${url}"
          class="block w-full h-auto"
          width="${size.width}"
          height="${size.height}"
          alt="Banner"
          @error="${this._handleBannerError}"
        />
      `;
    }

    return html`
      <div data-theme-image="light" data-banner-aspect="${aspect}">
        <img
          src="${url}"
          class="block w-full h-auto"
          width="${size.width}"
          height="${size.height}"
          alt="Banner"
          @error="${this._handleBannerError}"
        />
      </div>
      <div data-theme-image="dark" data-banner-aspect="${aspect}">
        <img
          src="${darkUrl}"
          class="block w-full h-auto"
          width="${size.width}"
          height="${size.height}"
          alt="Banner"
          loading="lazy"
          @error="${this._handleBannerError}"
        />
      </div>
    `;
  }

  _getCurrentItem() {
    return this.items.find((item) => item.current) || this.items[this.items.length - 1];
  }

  /**
   * Renders one mobile dropdown row, preserving links only for navigable items.
   * @param {object} item - Breadcrumb item to render
   * @returns {TemplateResult} Dropdown row template
   * @private
   */
  _renderMobileDropdownItem(item) {
    const isCurrent = item.current;

    if (isCurrent || !item.href) {
      return html`
        <div
          class="flex items-center gap-3 px-4 py-2.5 ${isCurrent ? "bg-stone-50" : ""} text-sm phone:min-h-11"
          role="option"
          aria-selected="${isCurrent}"
          aria-current="${isCurrent ? "page" : nothing}"
        >
          <span class="shrink-0 ${isCurrent ? "text-stone-600" : "text-stone-400"}">
            <div class="svg-icon size-4 bg-current icon-${item.icon}"></div>
          </span>
          <span class="${isCurrent ? "text-stone-900 font-medium" : "text-stone-600"} truncate flex-1">
            ${item.label}
          </span>
        </div>
      `;
    }

    return html`
      <a
        href="${item.href}"
        class="flex items-center gap-3 px-4 py-2.5 hover:bg-stone-50 transition-colors group text-sm phone:min-h-11"
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

  /**
   * Renders one desktop breadcrumb item with its leading separator.
   * @param {object} item - Breadcrumb item to render
   * @param {number} index - Item position in the breadcrumb trail
   * @returns {TemplateResult} Desktop breadcrumb item template
   * @private
   */
  _renderDesktopItem(item, index) {
    const isHome = item.icon === "home";
    const isLast = index === this.items.length - 1;
    const isCurrent = item.current || isLast;

    const separator = html`
      <li class="shrink-0" aria-hidden="true">
        <div class="svg-icon size-4 bg-stone-300 icon-arrow-right"></div>
      </li>
    `;

    const itemClass = `flex items-center gap-1.5 ${isHome ? "shrink-0" : "min-w-0 breadcrumb-item"}`;
    const labelClass = `${isHome ? "" : "truncate min-w-0"}`;

    const content = isCurrent
      ? html`
          <li class="${itemClass}" aria-current="page">
            <div class="svg-icon size-4 bg-stone-700 icon-${item.icon} shrink-0"></div>
            <span class="${labelClass} text-stone-700 font-medium">${item.label}</span>
          </li>
        `
      : !item.href
        ? html`
            <li class="${itemClass}">
              <div class="svg-icon size-4 bg-stone-500 icon-${item.icon} shrink-0"></div>
              <span class="${labelClass}">${item.label}</span>
            </li>
          `
        : html`
            <li class="${itemClass}">
              <a
                href="${item.href}"
                class="flex items-center gap-1.5 hover:text-stone-700 hover:underline min-w-0"
                hx-boost="true"
                hx-target="body"
              >
                <div class="svg-icon size-4 bg-stone-500 icon-${item.icon} shrink-0"></div>
                <span class="${labelClass}">${item.label}</span>
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
      <div
        class="container mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 pt-3 sm:pt-8 ${
          this.fullBleed ? "phone:px-0 phone:pt-0" : "phone:px-3 phone:pt-3"
        }"
      >
        <div
          class="bg-surface border border-stone-200 rounded-lg ${
            this.fullBleed ? "phone:rounded-none phone:border-x-0 phone:border-t-0" : ""
          }"
        >
          ${
            this.bannerMobileUrl
              ? html`
                  <div
                    class="w-full border-b border-stone-200 sm:hidden overflow-hidden rounded-t-lg phone:block ${
                      this.fullBleed ? "phone:rounded-none" : ""
                    }"
                    data-banner-aspect="${getBannerAspect(MOBILE_BANNER_SIZE)}"
                  >
                    ${this._renderBannerImages(this.bannerMobileUrl, this.bannerMobileDarkUrl, MOBILE_BANNER_SIZE)}
                  </div>
                `
              : ""
          }
          ${
            this.bannerUrl
              ? html`
                  <div
                    class="w-full border-b border-stone-200 hidden sm:block overflow-hidden rounded-t-lg phone:hidden"
                    data-banner-aspect="${getBannerAspect(DESKTOP_BANNER_SIZE)}"
                  >
                    ${this._renderBannerImages(this.bannerUrl, this.bannerDarkUrl, DESKTOP_BANNER_SIZE)}
                  </div>
                `
              : ""
          }
          <nav
            class="px-4 sm:px-6 lg:px-10 py-3 phone:py-0 ${this.fullBleed ? "phone:px-3" : "phone:px-4"}"
            aria-label="Breadcrumb"
          >
            <!-- Mobile breadcrumb dropdown -->
            <div class="relative sm:hidden phone:block">
              <button
                data-breadcrumb-trigger
                class="flex items-center gap-2 w-full text-sm phone:min-h-11"
                aria-expanded="${this._isOpen}"
                aria-haspopup="listbox"
                aria-controls="${this._dropdownId}"
                @click="${this._toggleDropdown}"
              >
                <div class="svg-icon size-4 bg-stone-400 icon-tree-list"></div>
                <span class="text-stone-600 truncate flex-1 text-left">${currentItem.label}</span>
                <!-- Tap cue: a mini button on phones, decorative since the whole row is the trigger -->
                <span
                  class="btn-primary-outline-anchor btn-mini size-7 shrink-0 p-0 not-phone:contents"
                  aria-hidden="true"
                >
                  <div
                    class="svg-icon size-3 bg-stone-400 icon-caret-down transition-transform duration-200 motion-reduce:transition-none phone:bg-current ${
                      this._isOpen ? "rotate-180" : ""
                    }"
                  ></div>
                </span>
              </button>
              <div
                id="${this._dropdownId}"
                data-breadcrumb-dropdown
                class="origin-top transition-all duration-150 ease-out motion-reduce:transition-none absolute top-full left-0 mt-3 -mx-4 w-[calc(100%+2rem)] bg-raised rounded-xl shadow-lg border border-stone-200 z-50 max-h-64 overflow-y-auto phone:mt-1 phone:z-[25] ${
                  this.fullBleed ? "phone:-mx-3 phone:w-[calc(100%+1.5rem)]" : ""
                } ${
                  this._isOpen
                    ? "opacity-100 scale-y-100 translate-y-0"
                    : "opacity-0 scale-y-95 -translate-y-1 pointer-events-none phone:invisible"
                }"
                role="listbox"
                aria-label="${isPhoneViewport() ? "Breadcrumb links" : nothing}"
              >
                <div class="py-1">${this.items.map((item) => this._renderMobileDropdownItem(item))}</div>
              </div>
            </div>

            <!-- Desktop breadcrumb -->
            <ol
              class="hidden sm:flex sm:items-center gap-2 text-sm text-stone-500 px-1 phone:hidden"
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

/**
 * Formats a banner size as a CSS aspect ratio.
 * @param {{height: number, width: number}} size - Natural banner size
 * @returns {string} Aspect ratio, such as `2428 / 192`
 */
const getBannerAspect = (size) => `${size.width} / ${size.height}`;

customElements.define("breadcrumb-nav", BreadcrumbNav);
