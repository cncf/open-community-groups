import { html, repeat } from "/static/vendor/js/lit-all.v3.3.3.min.js";
import "/static/js/common/actions-menu.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import "/static/js/common/media/logo-image.js";
import { computeUserInitials } from "/static/js/common/users/initials.js";
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
                      const displayName = speaker.name || speaker.username || "";
                      return html`
                        <tr class="border-b border-stone-200 odd:bg-white even:bg-stone-50/50">
                          <td class="px-4 py-3">
                            <div class="flex min-w-0 items-center gap-3">
                              <logo-image
                                image-url=${speaker.photo_url || ""}
                                placeholder=${computeUserInitials(speaker.name, speaker.username, 2)}
                                size="size-8"
                                font-size="text-xs"
                                hide-border="true"
                              ></logo-image>
                              <div class="min-w-0">
                                <div class="truncate font-medium text-stone-900">${displayName}</div>
                                <div class="truncate text-xs text-stone-500">@${speaker.username || ""}</div>
                              </div>
                            </div>
                          </td>
                          <td class="w-40 px-4 py-3 text-center">
                            ${
                              speaker.featured
                                ? html`<span
                                    class="inline-flex items-center justify-center"
                                    title="Featured speaker"
                                  >
                                    <span
                                      class="svg-icon size-4 icon-star bg-amber-500"
                                      aria-hidden="true"
                                    ></span>
                                    <span class="sr-only">Yes</span>
                                  </span>`
                                : html`<span class="sr-only">No</span>`
                            }
                          </td>
                          <td class="px-4 py-3 text-stone-700">${speaker.sessionNames.join(", ")}</td>
                          ${
                            hasActions
                              ? html`<td class="px-4 py-3 text-right">
                                  <details data-actions-menu class="group relative inline-block text-left">
                                    <summary
                                      class="btn-actions btn-tertiary flex cursor-pointer list-none items-center justify-center p-2 group-open:bg-stone-50 [&::-webkit-details-marker]:hidden"
                                      aria-label=${`Open session speaker actions for ${displayName}`}
                                    >
                                      <span class="svg-icon size-4 icon-vertical-dots"></span>
                                    </summary>
                                    <div
                                      class="dropdown absolute z-20 end-0 top-8 w-48 rounded-lg border border-stone-200 bg-white shadow"
                                    >
                                      <ul class="py-2 text-sm text-stone-700" role="menu">
                                        <li>
                                          <button
                                            type="button"
                                            class="flex w-full items-center gap-3 px-4 py-2 text-left transition-colors hover:bg-stone-100 disabled:cursor-not-allowed disabled:opacity-50"
                                            data-badge-award-open
                                            data-event-id=${this.eventId}
                                            data-user-ids=${speaker.user_id}
                                            role="menuitem"
                                            title=${
                                              this.awardsDisabled
                                                ? "Save contributor changes before awarding badges."
                                                : ""
                                            }
                                            ?disabled=${this.awardsDisabled}
                                          >
                                            <span
                                              class="svg-icon size-4 icon-certificate bg-stone-500"
                                            ></span>
                                            <span>Award badge</span>
                                          </button>
                                        </li>
                                      </ul>
                                    </div>
                                  </details>
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
