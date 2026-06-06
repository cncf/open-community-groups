import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import {
  getStatusColor,
  isLinkedToSession,
  isMessageRequired,
  isStatusAllowed,
} from "/static/js/dashboard/event/cfs-submissions-review-utils.js";

const renderStatusBoxes = ({ onStatusCheckChange, statusId: selectedStatusId, statuses, submission }) => {
  const reviewStatuses = statuses.filter((status) => status.cfs_submission_status_id !== "not-reviewed");
  const isLinked = isLinkedToSession(submission);

  return html`
    <div class="grid grid-cols-3 gap-3">
      ${reviewStatuses.map((status) => {
        const statusId = status?.cfs_submission_status_id || "";
        const isSelected = selectedStatusId === statusId;
        const color = getStatusColor(statusId);
        const isDisabled = isLinked && statusId !== "approved";

        return html`
          <label class="block ${isDisabled ? "cursor-not-allowed opacity-60" : "cursor-pointer"}">
            <input
              type="checkbox"
              value=${statusId}
              class="sr-only"
              .checked=${isSelected}
              @change=${(event) => onStatusCheckChange(event, statusId)}
              ?disabled=${isDisabled}
            />
            <div
              class="rounded-lg border p-3 transition bg-white ${isSelected
                ? `${color.border} ${color.ring}`
                : "border-stone-200"}"
            >
              <div class="flex items-center gap-2">
                <span
                  class="relative flex h-4 w-4 items-center justify-center rounded border
                    ${isSelected ? color.border : "border-stone-200"}"
                >
                  ${isSelected ? html`<div class="svg-icon size-3 icon-check ${color.dot}"></div>` : ""}
                </span>
                <span class="text-sm font-medium text-stone-700"> ${status?.display_name || ""} </span>
              </div>
            </div>
          </label>
        `;
      })}
    </div>
    <input type="hidden" name="status_id" .value=${selectedStatusId} />
  `;
};

/**
 * Renders the CFS review decision panel.
 * @param {Object} state Decision panel state and handlers.
 * @returns {import("lit").TemplateResult}
 */
export const renderCfsDecisionPanel = (state) => html`
  <section
    id="cfs-submission-tabpanel-decision"
    role="tabpanel"
    class="pt-5 space-y-8"
    ?hidden=${!state.isActive}
  >
    <div
      role="status"
      class="rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900"
    >
      This is the <span class="font-semibold">group's final decision</span> on this submission, not an
      individual assessment. Once saved, it is final. The speaker will receive this update and can review it
      in their Submissions tab.
    </div>

    <div>
      <label class="form-label">Decision</label>
      <div class="mt-3">${renderStatusBoxes(state)}</div>
      ${isLinkedToSession(state.submission)
        ? html`
            <p class="form-legend mt-2">
              This submission is linked to a session. Unlink it from the session before choosing a
              non-approved status.
            </p>
          `
        : ""}
    </div>

    <div>
      <label for="cfs-submission-message" class="form-label">
        Message for speaker ${isMessageRequired(state.statusId) ? html`<span class="asterisk">*</span>` : ""}
      </label>
      <div class="mt-2">
        <textarea
          id="cfs-submission-message"
          name="action_required_message"
          class="input-primary"
          maxlength=${state.messageMaxLength}
          rows="3"
          placeholder="Add a note for the speaker..."
          .value=${state.message}
          @input=${state.onMessageInput}
          ?required=${isMessageRequired(state.statusId)}
        ></textarea>
      </div>
      <p class="form-legend">
        Required when requesting changes. Explain what information or changes are needed.
      </p>
    </div>
  </section>
`;
