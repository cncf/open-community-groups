import { html } from "/static/vendor/js/lit-all.v3.2.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import "/static/js/common/avatar-image.js";

/**
 * PeopleList component for displaying a list of people with avatars.
 * Features expandable list with "show more/less" functionality.
 * Uses avatar-image component for handling profile images with fallback to initials.
 * @extends LitWrapper
 */
export class PeopleList extends LitWrapper {
  /**
   * Regex pattern to extract only alphabetic characters.
   * Removes emojis, numbers, and special characters while preserving international letters.
   * @static
   * @type {RegExp}
   */
  static LETTERS_ONLY_REGEX = /[^\p{L}]/gu;

  /**
   * Component properties definition
   * @property {Array} people - Array of person objects with name, photo, title, and company
   * @property {number} initialCount - Number of people to show initially before "show more" (default: 6)
   * @property {boolean} _showAll - Internal state tracking if all items are shown
   */
  static get properties() {
    return {
      people: { type: Array },
      initialCount: { type: Number },
      _showAll: { type: Boolean },
    };
  }

  constructor() {
    super();
    this.people = [];
    this.initialCount = 6;
    this._showAll = false;
  }

  /**
   * Toggles between showing all items and showing limited items.
   * Called when user clicks the show more/less button.
   * @private
   */
  _toggleShowAll() {
    this._showAll = !this._showAll;
  }

  /**
   * Removes non-alphabetic characters from a string.
   * Used to clean names before extracting initials.
   * @param {string} str - String to clean
   * @returns {string} String containing only alphabetic characters
   * @private
   */
  _cleanString(str) {
    if (!str) return "";
    return str.replace(PeopleList.LETTERS_ONLY_REGEX, "");
  }

  /**
   * Generates initials from a full name.
   * Splits name by spaces, removes special characters, and returns up to two uppercase letters.
   * @param {string} name - Person's full name
   * @returns {string} Initials or "-" if no valid name provided
   * @private
   */
  _getInitials(name) {
    if (!name) return "-";

    const nameParts = name.trim().split(/\s+/);
    const firstName = nameParts[0] || "";
    const lastName = nameParts.length > 1 ? nameParts[nameParts.length - 1] : "";

    const cleanFirst = this._cleanString(firstName);
    const cleanLast = this._cleanString(lastName);

    const firstInitial = cleanFirst.charAt(0).toUpperCase();
    const lastInitial = cleanLast.charAt(0).toUpperCase();

    if (firstInitial && lastInitial) {
      return `${firstInitial}${lastInitial}`;
    } else if (firstInitial) {
      return firstInitial;
    } else if (lastInitial) {
      return lastInitial;
    }
    return "-";
  }

  /**
   * Renders avatar component for a person.
   * Passes image URL and calculated initials to avatar-image component.
   * @param {Object} person - Person object with photo_url and name
   * @returns {TemplateResult} Avatar component template
   * @private
   */
  _renderAvatar(person) {
    const initials = this._getInitials(person.name);

    return html`
      <avatar-image image-url="${person.photo_url || ""}" placeholder="${initials}"></avatar-image>
    `;
  }

  /**
   * Renders a single person list item.
   * Includes avatar, name, and title/company information.
   * @param {Object} person - Person object to render
   * @returns {TemplateResult} Person list item template
   * @private
   */
  _renderPerson(person) {
    return html`
      <div class="flex items-center gap-3 p-3">
        <!-- Avatar -->
        ${this._renderAvatar(person)}
        <!-- End avatar -->

        <!-- Name and details -->
        <div class="flex-1 min-w-0">
          <h3 class="text-sm font-semibold text-stone-900 truncate">${person.name}</h3>
          ${person.title
            ? html`<p class="text-xs text-stone-600 mt-1 truncate">${person.title}</p>`
            : person.company
            ? html`<p class="text-xs text-stone-600 mt-1 truncate">${person.company}</p>`
            : ""}
        </div>
        <!-- End name and details -->
      </div>
    `;
  }

  /**
   * Main render method for the component.
   * Handles empty state, list rendering, and show more/less functionality.
   * @returns {TemplateResult} Complete component template
   */
  render() {
    if (!this.people || this.people.length === 0) {
      return html``;
    }

    const hasMore = this.people.length > this.initialCount;
    const peopleToShow = this._showAll ? this.people : this.people.slice(0, this.initialCount);

    return html`
      <div>
        <!-- People list -->
        <div class="border border-stone-200 rounded-lg divide-y divide-stone-200">
          ${peopleToShow.map((person) => this._renderPerson(person))}

          <!-- Show more/less link as list item -->
          ${hasMore
            ? html`
                <div class="p-3">
                  <button
                    @click="${this._toggleShowAll}"
                    class="group inline-flex items-center gap-1.5 text-xs/6 text-stone-500/75 hover:text-stone-700 focus:ring-0 focus:outline-none focus:ring-stone-300 font-medium"
                  >
                    <span
                      class="inline-flex items-center justify-center border border-stone-200 group-hover:bg-stone-700 rounded-full p-1"
                    >
                      <div
                        class="svg-icon size-3 bg-stone-500 group-hover:bg-white ${this._showAll
                          ? "icon-caret-up"
                          : "icon-caret-down"}"
                      ></div>
                    </span>
                    <span>
                      ${this._showAll ? "Show less" : `Show ${this.people.length - this.initialCount} more`}
                    </span>
                  </button>
                </div>
              `
            : ""}
          <!-- End show more/less link -->
        </div>
        <!-- End people list -->
      </div>
    `;
  }
}

customElements.define("people-list", PeopleList);
