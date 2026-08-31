import { html } from "lit";
import "/static/js/common/actions-menu.js";
import "/static/js/common/media/logo-image.js";
import { computeUserInitials } from "/static/js/common/users/initials.js";

const MENU_ITEM_CLASSES =
  "flex w-full items-center gap-3 px-4 py-2 text-left transition-colors hover:bg-stone-100 disabled:cursor-not-allowed disabled:opacity-50";

/**
 * Returns the display name used in contributor table rows.
 * @param {{name?: string, username?: string}} contributor Contributor data
 * @returns {string} Contributor name or username
 */
export const contributorDisplayName = (contributor) => contributor.name || contributor.username || "";

/**
 * Renders a contributor action menu with optional badge award and delete actions.
 * @param {object} options Action menu options
 * @param {string} options.actionLabel Contributor type used in the menu label
 * @param {boolean} [options.awardsDisabled] Whether badge awards require saving first
 * @param {boolean} [options.canAwardBadges] Whether badge awards are available
 * @param {object} options.contributor Contributor data
 * @param {boolean} [options.deleteDisabled] Whether deleting is disabled
 * @param {string} [options.eventId] Event identifier used to award a badge
 * @param {() => void} [options.onDelete] Optional delete handler
 * @returns {import("lit").TemplateResult} Contributor action menu template
 */
export const renderContributorActions = ({
  actionLabel,
  awardsDisabled = false,
  canAwardBadges = false,
  contributor,
  deleteDisabled = false,
  eventId = "",
  onDelete,
}) => {
  const displayName = contributorDisplayName(contributor);
  const canAward = canAwardBadges && eventId;

  return html`
    <details data-actions-menu class="group relative inline-block text-left">
      <summary
        class="btn-actions btn-tertiary flex cursor-pointer list-none items-center justify-center p-2 group-open:bg-stone-50 [&::-webkit-details-marker]:hidden"
        aria-label=${`Open ${actionLabel} actions for ${displayName}`}
      >
        <span class="svg-icon size-4 icon-vertical-dots"></span>
      </summary>
      <div class="dropdown absolute z-20 end-0 top-8 w-48 rounded-lg border border-stone-200 bg-white shadow">
        <ul class="py-2 text-sm text-stone-700" role="menu">
          ${
            canAward
              ? html`<li>
                  <button
                    type="button"
                    class=${MENU_ITEM_CLASSES}
                    data-badge-award-open
                    data-event-id=${eventId}
                    data-user-ids=${contributor.user_id}
                    role="menuitem"
                    title=${awardsDisabled ? "Save contributor changes before awarding badges." : ""}
                    ?disabled=${awardsDisabled}
                  >
                    <span class="svg-icon size-4 icon-certificate bg-stone-500"></span>
                    <span>Award badge</span>
                  </button>
                </li>`
              : ""
          }
          ${
            onDelete
              ? html`<li>
                  <button
                    type="button"
                    class=${MENU_ITEM_CLASSES}
                    role="menuitem"
                    ?disabled=${deleteDisabled}
                    @click=${onDelete}
                  >
                    <span class="svg-icon size-4 icon-trash bg-stone-500"></span>
                    <span>Delete</span>
                  </button>
                </li>`
              : ""
          }
        </ul>
      </div>
    </details>
  `;
};

/**
 * Renders a contributor identity cell with an avatar and username.
 * @param {{name?: string, photo_url?: string, username?: string}} contributor Contributor data
 * @returns {import("lit").TemplateResult} Contributor identity template
 */
export const renderContributorIdentity = (contributor) => {
  const displayName = contributorDisplayName(contributor);

  return html`
    <div class="flex min-w-0 items-center gap-3">
      <logo-image
        image-url=${contributor.photo_url || ""}
        placeholder=${computeUserInitials(contributor.name, contributor.username, 2)}
        size="size-8"
        font-size="text-xs"
        hide-border="true"
      ></logo-image>
      <div class="min-w-0">
        <div class="truncate font-medium text-stone-900">${displayName}</div>
        <div class="truncate text-xs text-stone-500">@${contributor.username || ""}</div>
      </div>
    </div>
  `;
};

/**
 * Renders the featured-speaker state used by contributor tables.
 * @param {boolean} featured Whether the contributor is featured
 * @returns {import("lit").TemplateResult} Featured state template
 */
export const renderFeaturedContributorState = (featured) =>
  featured
    ? html`<span class="inline-flex items-center justify-center" title="Featured speaker">
        <span class="svg-icon size-4 icon-star bg-amber-500" aria-hidden="true"></span>
        <span class="sr-only">Yes</span>
      </span>`
    : html`<span class="sr-only">No</span>`;
