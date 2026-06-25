import { html } from "/static/vendor/js/lit-all.v3.3.3.min.js";

const TAB_BUTTON_CLASS =
  "cursor-pointer inline-flex items-center justify-center p-2 sm:p-3 border-b-2 " +
  "border-transparent rounded-t-lg hover:text-stone-600 hover:border-stone-300 " +
  "data-[active=true]:text-primary-500 data-[active=true]:border-primary-500 " +
  "text-nowrap w-32";

/**
 * Renders pending changes alert for the review footer.
 * @param {boolean} hasPendingChanges Whether the form has unsaved changes.
 * @returns {import("lit").TemplateResult}
 */
export const renderCfsPendingChangesAlert = (hasPendingChanges) => {
  if (!hasPendingChanges) {
    return html``;
  }

  return html`
    <div
      class="inline-flex items-center gap-3 rounded-md border border-primary-200
      bg-primary-50 px-3 py-2 text-primary-900"
    >
      <div class="svg-icon size-4 bg-primary-700 icon-clock shrink-0"></div>
      <p class="text-sm">You have pending changes. Click Save to apply these updates.</p>
    </div>
  `;
};

/**
 * Renders a CFS review tab button.
 * @param {Object} tab Tab definition.
 * @returns {import("lit").TemplateResult}
 */
const renderReviewTabButton = (tab) => {
  const isActive = tab.id === tab.activeTab;

  return html`
    <li>
      <button
        type="button"
        role="tab"
        aria-controls=${tab.panelId}
        aria-selected=${isActive ? "true" : "false"}
        data-active=${isActive ? "true" : "false"}
        class=${TAB_BUTTON_CLASS}
        @click=${() => tab.onSelect(tab.id)}
      >
        ${tab.label}
      </button>
    </li>
  `;
};

/**
 * Renders the CFS review tabs navigation.
 * @param {Object} state Tab navigation state.
 * @returns {import("lit").TemplateResult}
 */
export const renderCfsReviewTabsNavigation = (state) => {
  const tabs = [
    {
      id: state.tabs.DETAILS,
      label: "Details",
      panelId: "cfs-submission-tabpanel-details",
    },
    {
      id: state.tabs.RATINGS,
      label: "Ratings",
      panelId: "cfs-submission-tabpanel-ratings",
    },
    {
      id: state.tabs.DECISION,
      label: "Decision",
      panelId: "cfs-submission-tabpanel-decision",
    },
  ];

  return html`
    <ul
      class="flex flex-wrap space-x-2 -mb-px text-sm font-medium text-center
        border-b border-stone-200"
      role="tablist"
      aria-label="Submission review tabs"
    >
      ${tabs.map((tab) =>
        renderReviewTabButton({
          ...tab,
          activeTab: state.activeTab,
          onSelect: state.onSelect,
        }),
      )}
    </ul>
  `;
};
