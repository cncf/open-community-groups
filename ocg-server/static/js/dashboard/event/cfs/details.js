import { html } from "/static/vendor/js/lit-all.v3.3.3.min.js";
import { computeUserInitials } from "/static/js/common/users/initials.js";
import { renderTrustedHtml } from "/static/js/common/trusted-lit-html.js";

/**
 * Renders a badge row for a person.
 * @param {Object} person Person payload.
 * @returns {import("lit").TemplateResult}
 */
export const renderCfsPersonRow = (person) => {
  const name = person?.name || person?.username || "";
  const photoUrl = person?.photo_url || "";
  const initials = computeUserInitials(name, person?.username || "", 2);

  return html`
    <div
      class="inline-flex items-center gap-2 bg-stone-100 rounded-full ps-1 pe-2 py-1 max-w-full"
      title=${name}
    >
      <logo-image
        class="shrink-0"
        image-url=${photoUrl}
        placeholder=${initials}
        size="size-[24px]"
        font-size="text-xs"
        hide-border
      ></logo-image>
      <span class="text-sm text-stone-700 truncate">${name}</span>
    </div>
  `;
};

/**
 * Renders proposal metadata badges.
 * @param {Object} proposal Proposal payload.
 * @returns {import("lit").TemplateResult}
 */
const renderCfsProposalMeta = (proposal) => {
  const level = proposal?.session_proposal_level_name;
  const duration = proposal?.duration_minutes;
  return html`
    ${
      level
        ? html`
            <div>
              <div class="proposal-section-title">Level</div>
              <div class="mt-1 text-sm text-stone-700">${level}</div>
            </div>
          `
        : ""
    }
    ${
      duration
        ? html`
            <div>
              <div class="proposal-section-title">Duration</div>
              <div class="mt-1 text-sm text-stone-700">${duration} min</div>
            </div>
          `
        : ""
    }
  `;
};

/**
 * Renders labels editor for the details tab.
 * @param {Object} state Details label state.
 * @returns {import("lit").TemplateResult}
 */
const renderCfsDetailsLabels = (state) => {
  if (state.labels.length === 0) {
    return html``;
  }

  return html`
    <div>
      <label for="cfs-submission-labels" class="form-label">Labels</label>
      <div class="mt-2">
        <cfs-label-selector
          id="cfs-submission-labels"
          name="label_ids"
          .labels=${state.labels}
          .selected=${state.selectedLabelIds}
          close-on-select
          max-selected="10"
          legend="Add labels to categorize this submission for your review team."
          placeholder="Search labels"
          @change=${state.onLabelsChange}
        ></cfs-label-selector>
      </div>
    </div>
  `;
};

/**
 * Renders submission details panel.
 * @param {Object} state Details panel state.
 * @returns {import("lit").TemplateResult}
 */
export const renderCfsDetailsPanel = (state) => {
  const proposal = state.submission?.session_proposal || {};
  const coSpeaker = proposal?.co_speaker;

  return html`
    <section
      id="cfs-submission-tabpanel-details"
      role="tabpanel"
      class="pt-5 space-y-8"
      ?hidden=${!state.isActive}
    >
      <div class="flex flex-col md:flex-row gap-6">
        <div class="flex-1 space-y-4 min-w-0">
          <div>
            <div class="proposal-section-title">Title</div>
            <div class="mt-2 text-lg text-stone-800 font-medium">${proposal?.title || ""}</div>
          </div>

          <div>
            <div class="proposal-section-title">Description</div>
            <div class="mt-2 max-h-[200px] overflow-y-auto text-stone-700 text-sm/6 markdown">
              ${
                proposal?.description_html
                  ? renderTrustedHtml(proposal.description_html)
                  : proposal?.description || ""
              }
            </div>
          </div>
        </div>

        <div class="w-full md:w-72 shrink-0 space-y-4 md:border-l md:border-stone-100 md:pl-6">
          ${renderCfsProposalMeta(proposal)}

          <div>
            <div class="proposal-section-title">Speaker</div>
            <div class="mt-2">
              ${state.submission?.speaker ? renderCfsPersonRow(state.submission.speaker) : ""}
            </div>
          </div>

          ${
            coSpeaker
              ? html`
                  <div>
                    <div class="proposal-section-title">Co-speaker</div>
                    <div class="mt-2">${renderCfsPersonRow(coSpeaker)}</div>
                  </div>
                `
              : ""
          }
        </div>
      </div>

      ${
        state.labels.length > 0
          ? html` <div class="border-t border-stone-200 pt-5">${renderCfsDetailsLabels(state)}</div> `
          : ""
      }
    </section>
  `;
};
