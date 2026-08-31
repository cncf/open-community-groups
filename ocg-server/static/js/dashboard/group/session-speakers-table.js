import { html } from "lit";
import { repeat } from "lit/directives/repeat.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import {
  renderContributorActions,
  renderContributorIdentity,
  renderFeaturedContributorState,
} from "/static/js/common/users/contributor-row.js";
import { parseSessionsAttribute } from "/static/js/dashboard/event/sessions/attributes.js";
import { normalizeSpeakers, speakerKey } from "/static/js/dashboard/event/sessions/speaker-utils.js";

/** Read-only event contributor table for speakers assigned at session level. */
export class SessionSpeakersTable extends LitWrapper {
  static properties = {
    awardsDisabled: { type: Boolean, attribute: "awards-disabled" },
    canAwardBadges: { type: Boolean, attribute: "can-award-badges" },
    eventId: { type: String, attribute: "event-id" },
    sessions: { type: Array },
  };

  constructor() {
    super();
    this.awardsDisabled = false;
    this.canAwardBadges = false;
    this.eventId = "";
    this.sessions = [];
  }

  connectedCallback() {
    super.connectedCallback();
    this.sessions = parseSessionsAttribute(this.sessions);
  }

  /** Returns one row per speaker with every associated session name. */
  _rows() {
    const rows = new Map();
    parseSessionsAttribute(this.sessions).forEach((session) => {
      normalizeSpeakers(session.speakers).forEach((speaker) => {
        const key = speakerKey(speaker);
        if (!key) return;
        const current = rows.get(key) || { ...speaker, sessionNames: new Set() };
        current.featured = current.featured || speaker.featured;
        if (session.name) {
          current.sessionNames.add(session.name);
        }
        rows.set(key, current);
      });
    });

    return Array.from(rows.values())
      .map((speaker) => ({ ...speaker, sessionNames: Array.from(speaker.sessionNames).sort() }))
      .sort((left, right) =>
        String(left.name || left.username || "").localeCompare(String(right.name || right.username || "")),
      );
  }

  render() {
    const rows = this._rows();
    const hasActions = this.canAwardBadges && this.eventId;

    return html`
      <div class="mt-4 overflow-visible">
        <table class="w-full text-left text-sm text-stone-600" aria-label="Session-level speakers">
          <thead class="border-b border-stone-200 bg-stone-100 text-xs uppercase text-stone-700">
            <tr>
              <th scope="col" class="px-4 py-3">Name</th>
              <th scope="col" class="w-40 px-4 py-3 text-center">Featured</th>
              <th scope="col" class="px-4 py-3">Sessions</th>
              ${
                hasActions
                  ? html`<th scope="col" class="w-[72px] px-4 py-3">
                      <span class="sr-only">Actions</span>
                    </th>`
                  : ""
              }
            </tr>
          </thead>
          <tbody>
            ${
              rows.length === 0
                ? html`<tr class="border-b border-stone-200 bg-white">
                    <td class="px-8 py-12 text-center text-stone-500" colspan=${hasActions ? 4 : 3}>
                      No session-level speakers added yet.
                    </td>
                  </tr>`
                : repeat(
                    rows,
                    (speaker) => speakerKey(speaker),
                    (speaker) => {
                      return html`
                        <tr class="border-b border-stone-200 odd:bg-white even:bg-stone-50/50">
                          <td class="px-4 py-3">${renderContributorIdentity(speaker)}</td>
                          <td class="w-40 px-4 py-3 text-center">
                            ${renderFeaturedContributorState(speaker.featured)}
                          </td>
                          <td class="px-4 py-3 text-stone-700">${speaker.sessionNames.join(", ")}</td>
                          ${
                            hasActions
                              ? html`<td class="px-4 py-3 text-right">
                                  ${renderContributorActions({
                                    actionLabel: "session speaker",
                                    awardsDisabled: this.awardsDisabled,
                                    canAwardBadges: this.canAwardBadges,
                                    contributor: speaker,
                                    eventId: this.eventId,
                                  })}
                                </td>`
                              : ""
                          }
                        </tr>
                      `;
                    },
                  )
            }
          </tbody>
        </table>
      </div>
    `;
  }
}

customElements.define("session-speakers-table", SessionSpeakersTable);
