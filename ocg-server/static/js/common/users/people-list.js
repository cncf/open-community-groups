import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { computeUserInitials } from "/static/js/common/common.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { parseJsonAttribute } from "/static/js/common/utils.js";
import "/static/js/common/media/logo-image.js";

/**
 * PeopleList renders a compact, expandable list of people.
 */
export class PeopleList extends LitWrapper {
  static get properties() {
    return {
      people: { type: Array },
      initialCount: { type: Number, attribute: "initial-count" },
      _expanded: { state: true },
    };
  }

  constructor() {
    super();
    this.people = [];
    this.initialCount = 4;
    this._expanded = false;
  }

  connectedCallback() {
    super.connectedCallback();
    this.people = parseJsonAttribute(this.people, []);
  }

  _cleanString(value) {
    return String(value || "").replace(/[^\p{L}]/gu, "");
  }

  _toggleExpanded() {
    this._expanded = !this._expanded;
  }

  _renderPerson(person) {
    const name = person?.name || person?.username || "";
    const subtitle = [person?.title, person?.company].filter(Boolean).join(", ");

    return html`
      <li class="flex items-center gap-3">
        <logo-image
          image-url=${person?.photo_url || ""}
          placeholder=${computeUserInitials(name, person?.username || "", 2)}
          size="size-10"
          font-size="text-xs"
        >
        </logo-image>
        <div class="min-w-0">
          <h3 class="truncate text-sm font-semibold text-stone-900">${name}</h3>
          ${subtitle ? html`<p class="truncate text-xs text-stone-600">${subtitle}</p>` : ""}
        </div>
      </li>
    `;
  }

  render() {
    const people = Array.isArray(this.people) ? this.people : [];
    if (people.length === 0) {
      return html``;
    }

    const visiblePeople = this._expanded ? people : people.slice(0, this.initialCount);
    const hiddenCount = Math.max(people.length - visiblePeople.length, 0);

    return html`
      <ul class="space-y-3">
        ${visiblePeople.map((person) => this._renderPerson(person))}
      </ul>
      ${people.length > this.initialCount
        ? html`
            <button
              type="button"
              class="mt-4 text-sm font-semibold text-primary-700"
              @click=${this._toggleExpanded}
            >
              ${this._expanded ? "Show less" : `Show ${hiddenCount} more`}
            </button>
          `
        : ""}
    `;
  }
}

customElements.define("people-list", PeopleList);
