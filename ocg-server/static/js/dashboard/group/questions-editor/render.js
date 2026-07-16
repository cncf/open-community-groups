import { html } from "/static/vendor/js/lit-all.v3.3.3.min.js";
import { QUESTION_TYPES, getQuestionTypeLabel } from "/static/js/dashboard/group/questions-editor/model.js";

/**
 * Renders the complete editor.
 * @param {QuestionsEditor} editor Questions editor element
 * @returns {unknown} Lit template
 */
const renderQuestionsEditor = (editor) => html`
  ${renderHiddenFields(editor)}
  <div class="w-full space-y-8">
    ${editor.questions.length > 0 && !editor.disabled ? renderQuestionEditingWarning() : ""}
    <div class="space-y-5">
      <div class="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
        <div class="text-sm font-semibold text-stone-700">
          ${editor.questions.length} ${editor.questions.length === 1 ? "question" : "questions"}
          <span class="mx-2 text-stone-400">•</span>
          ${editor.questions.filter((question) => question.required).length} required
        </div>
        <button
          type="button"
          class="btn-primary-outline btn-mini inline-flex items-center justify-center gap-2"
          ?disabled=${editor.disabled}
          @click=${() => editor._addQuestion()}
        >
          <div class="svg-icon size-4 icon-add-circle"></div>
          Add question
        </button>
      </div>

      <div class="mt-5 space-y-3">
        ${
          editor.questions.length === 0
            ? renderEmptyState(editor)
            : editor.questions.map((question, questionIndex) =>
                renderQuestionCard(editor, question, questionIndex),
              )
        }
      </div>
    </div>
  </div>
  ${renderQuestionModal(editor)}
`;

/**
 * Renders the warning shown while registration questions can still be edited.
 * @returns {unknown} Lit template
 */
const renderQuestionEditingWarning = () => html`
  <div
    data-question-editing-warning
    class="w-full rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900"
  >
    Questionnaire questions cannot be edited after an attendee has submitted answers.
  </div>
`;

/**
 * Renders hidden inputs using the serde_qs payload structure.
 * @param {QuestionsEditor} editor Questions editor element
 * @returns {unknown} Lit template
 */
const renderHiddenFields = (editor) => html`
  <input type="hidden" name="${editor.name}_present" value="true" />
  ${editor.questions.flatMap((question, questionIndex) => {
    const questionPrefix = `${editor.name}[${questionIndex}]`;
    return [
      html`<input type="hidden" name="${questionPrefix}[id]" value=${question.id} />`,
      html`<input type="hidden" name="${questionPrefix}[kind]" value=${question.kind} />`,
      html`<input type="hidden" name="${questionPrefix}[prompt]" value=${question.prompt.trim()} />`,
      html`<input
        type="hidden"
        name="${questionPrefix}[required]"
        value=${question.required ? "true" : "false"}
      />`,
      ...question.options.map((option, optionIndex) => {
        const optionPrefix = `${questionPrefix}[options][${optionIndex}]`;
        return html`
          <input type="hidden" name="${optionPrefix}[id]" value=${option.id} />
          <input type="hidden" name="${optionPrefix}[label]" value=${option.label.trim()} />
        `;
      }),
    ];
  })}
`;

/**
 * Renders the empty state.
 * @param {QuestionsEditor} editor Questions editor element
 * @returns {unknown} Lit template
 */
const renderEmptyState = (editor) => {
  const message = editor.disabled
    ? "No registration questions were added for this event."
    : 'No registration questions yet. Click "Add question" to create one.';

  return html`<div class="py-8 text-center text-sm italic text-stone-400">${message}</div>`;
};

/**
 * Renders a question card.
 * @param {QuestionsEditor} editor Questions editor element
 * @param {object} question Question state
 * @param {number} questionIndex Question index
 * @returns {unknown} Lit template
 */
const renderQuestionCard = (editor, question, questionIndex) => html`
  <div
    class=${[
      "flex items-start gap-2",
      editor._draggedQuestionIndex === questionIndex ? "opacity-70" : "",
    ].join(" ")}
    @dragover=${(event) => editor._handleQuestionDragOver(event, questionIndex)}
    @dragleave=${() => editor._handleQuestionDragLeave(questionIndex)}
    @drop=${(event) => editor._handleQuestionDrop(event, questionIndex)}
  >
    <button
      type="button"
      class="shrink-0 rounded-full p-2 transition-colors hover:bg-stone-100 ${
        editor.disabled || editor.questions.length <= 1
          ? "cursor-not-allowed opacity-60"
          : "cursor-grab active:cursor-grabbing"
      }"
      draggable=${editor.disabled || editor.questions.length <= 1 ? "false" : "true"}
      ?disabled=${editor.disabled || editor.questions.length <= 1}
      @dragstart=${(event) => editor._handleQuestionDragStart(event, questionIndex)}
      @dragend=${() => editor._clearQuestionDragState()}
      @keydown=${(event) => editor._handleQuestionHandleKeydown(event, questionIndex)}
      aria-label="Reorder question"
      title="Drag to reorder"
    >
      <div class="svg-icon size-4 icon-drag bg-stone-600"></div>
    </button>
    <div
      class=${[
        "min-w-0 flex-1 rounded-md border border-stone-200 bg-white p-4",
        editor._dragOverQuestionIndex === questionIndex &&
        editor._draggedQuestionIndex !== null &&
        editor._draggedQuestionIndex !== questionIndex
          ? "ring-2 ring-primary-300"
          : "",
      ].join(" ")}
    >
      <div class="flex items-start gap-4">
        <div
          class="flex size-6 shrink-0 items-center justify-center rounded-full bg-stone-100 text-xs font-semibold leading-6 text-stone-900"
        >
          ${questionIndex + 1}
        </div>
        <div class="min-w-0 flex-1">
          <div class="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
            <div class="min-w-0">
              <div class="font-semibold text-stone-900">${question.prompt || "Untitled question"}</div>
              <div class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-stone-600">
                <span class="text-stone-500">${getQuestionTypeLabel(question.kind)}</span>
                ${
                  question.required
                    ? html`
                        <span class="text-stone-400">•</span>
                        <span class="font-medium text-stone-700">Required</span>
                      `
                    : ""
                }
              </div>
            </div>

            <div class="flex shrink-0 items-center gap-1">
              <button
                type="button"
                class="rounded-full p-2 transition-colors hover:bg-stone-100 ${
                  editor.disabled ? "cursor-not-allowed opacity-60" : ""
                }"
                ?disabled=${editor.disabled}
                @click=${() => editor._openQuestionModal(questionIndex)}
                aria-label="Edit question"
                title="Edit"
              >
                <div class="svg-icon size-4 icon-pencil bg-stone-600"></div>
              </button>
              <button
                type="button"
                class="rounded-full p-2 transition-colors hover:bg-stone-100 ${
                  editor.disabled ? "cursor-not-allowed opacity-60" : ""
                }"
                ?disabled=${editor.disabled}
                @click=${() => editor._removeQuestion(questionIndex)}
                aria-label="Delete question"
                title="Delete"
              >
                <div class="svg-icon size-4 icon-trash bg-stone-600"></div>
              </button>
            </div>
          </div>
          ${question.options.length > 0 ? renderOptionPreview(question.options) : ""}
        </div>
      </div>
    </div>
  </div>
`;

/**
 * Renders option preview badges for a question card.
 * @param {object[]} options Question options
 * @returns {unknown} Lit template
 */
const renderOptionPreview = (options) => html`
  <div class="mt-4 flex min-w-0 flex-wrap gap-2">
    ${options.map(
      (option) => html`
        <span
          class="inline-block max-w-full truncate rounded-full border border-stone-200 bg-stone-50 px-3 py-1 text-sm font-medium text-stone-700"
          title=${option.label || "Untitled option"}
        >
          ${option.label || "Untitled option"}
        </span>
      `,
    )}
  </div>
`;

/**
 * Renders the add/edit question modal.
 * @param {QuestionsEditor} editor Questions editor element
 * @returns {unknown} Lit template
 */
const renderQuestionModal = (editor) => html`
  <div
    class="fixed inset-0 z-[1000] ${
      editor._isModalOpen ? "flex" : "hidden"
    } items-center justify-center overflow-y-auto overflow-x-hidden"
    role="dialog"
    aria-modal="true"
    aria-labelledby="question-modal-title"
    data-pending-changes-ignore
  >
    <div class="absolute inset-0 bg-stone-950 opacity-35" @click=${() => editor._closeQuestionModal()}></div>
    <div class="modal-panel max-w-6xl p-4">
      <div class="modal-card rounded-lg">
        <div class="flex shrink-0 items-center justify-between border-b border-stone-200 p-5">
          <h3 id="question-modal-title" class="text-xl font-semibold text-stone-900">
            ${editor._isNewQuestion ? "Add question" : "Edit question"}
          </h3>
          <button
            type="button"
            class="group inline-flex h-8 w-8 items-center justify-center rounded-lg bg-transparent text-sm text-stone-400 transition-colors hover:bg-stone-100"
            ?disabled=${!editor._isModalOpen}
            @click=${() => editor._closeQuestionModal()}
          >
            <div
              class="svg-icon h-4 w-4 bg-stone-400 transition-colors group-hover:bg-stone-600 icon-close"
            ></div>
            <span class="sr-only">Close modal</span>
          </button>
        </div>

        <div class="modal-body flex-1 space-y-6 p-5">
          <div>
            <label class="form-label" for="question-prompt-draft">Question</label>
            <div class="mt-2">
              <input
                id="question-prompt-draft"
                data-question-modal-field
                class="input-primary"
                type="text"
                maxlength="500"
                placeholder="e.g. Company name"
                required
                .value=${editor._draftQuestion?.prompt || ""}
                ?disabled=${!editor._isModalOpen}
                @input=${(event) => editor._updateDraftQuestion({ prompt: event.target.value })}
              />
            </div>
          </div>

          <div class="max-w-xs">
            <label class="form-label" for="question-kind-draft">Type</label>
            <div class="mt-2">
              <select
                id="question-kind-draft"
                class="select-primary"
                .value=${editor._draftQuestion?.kind || "free-text"}
                ?disabled=${!editor._isModalOpen}
                @change=${(event) => editor._updateDraftQuestion({ kind: event.target.value })}
              >
                ${QUESTION_TYPES.map(
                  ([value, label]) =>
                    html`<option value=${value} ?selected=${editor._draftQuestion?.kind === value}>
                      ${label}
                    </option>`,
                )}
              </select>
            </div>
          </div>

          <label class="inline-flex cursor-pointer items-center">
            <input
              type="checkbox"
              class="peer sr-only"
              .checked=${editor._draftQuestion?.required || false}
              ?disabled=${!editor._isModalOpen}
              @change=${(event) => editor._updateDraftQuestion({ required: event.target.checked })}
            />
            <div
              class="relative h-6 w-11 rounded-full bg-stone-200 peer peer-checked:bg-primary-500 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-primary-300 after:absolute after:start-0.5 after:top-0.5 after:h-5 after:w-5 after:rounded-full after:border after:border-stone-200 after:bg-white after:transition-all after:content-[''] peer-checked:after:translate-x-full peer-checked:after:border-white rtl:peer-checked:after:-translate-x-full"
            ></div>
            <span class="ms-3 text-sm font-medium text-stone-900">Required</span>
          </label>

          ${editor._draftQuestion && editor._draftQuestion.kind !== "free-text" ? renderDraftOptions(editor) : ""}
        </div>

        <div class="flex shrink-0 items-center justify-end gap-3 border-t border-stone-200 p-5">
          <button
            type="button"
            class="btn-secondary"
            ?disabled=${!editor._isModalOpen}
            @click=${() => editor._closeQuestionModal()}
          >
            Cancel
          </button>
          <button
            type="button"
            class="btn-primary"
            ?disabled=${!editor._isModalOpen}
            @click=${() => editor._saveQuestion()}
          >
            ${editor._isNewQuestion ? "Add question" : "Save question"}
          </button>
        </div>
      </div>
    </div>
  </div>
`;

/**
 * Renders option controls for the draft question.
 * @param {QuestionsEditor} editor Questions editor element
 * @returns {unknown} Lit template
 */
const renderDraftOptions = (editor) => html`
  <div class="space-y-3">
    <div class="flex items-center justify-between gap-3">
      <div class="form-label">Options</div>
      <button
        type="button"
        class="btn-primary-outline btn-mini inline-flex items-center justify-center gap-2"
        ?disabled=${!editor._isModalOpen}
        @click=${() => editor._addDraftOption()}
      >
        <div class="svg-icon size-3 icon-add-circle"></div>
        Add option
      </button>
    </div>
    ${editor._draftQuestion.options.map(
      (option, optionIndex) => html`
        <div
          class=${[
            "flex items-center gap-2 rounded-md",
            editor._dragOverOptionIndex === optionIndex &&
            editor._draggedOptionIndex !== null &&
            editor._draggedOptionIndex !== optionIndex
              ? "ring-2 ring-primary-300"
              : "",
            editor._draggedOptionIndex === optionIndex ? "opacity-70" : "",
          ].join(" ")}
          @dragover=${(event) => editor._handleDraftOptionDragOver(event, optionIndex)}
          @dragleave=${() => editor._handleDraftOptionDragLeave(optionIndex)}
          @drop=${(event) => editor._handleDraftOptionDrop(event, optionIndex)}
        >
          <button
            type="button"
            class="shrink-0 rounded-full p-2 transition-colors hover:bg-stone-100 ${
              !editor._isModalOpen || editor._draftQuestion.options.length <= 1
                ? "cursor-not-allowed opacity-60"
                : "cursor-grab active:cursor-grabbing"
            }"
            draggable="true"
            ?disabled=${!editor._isModalOpen || editor._draftQuestion.options.length <= 1}
            @dragstart=${(event) => editor._handleDraftOptionDragStart(event, optionIndex)}
            @dragend=${() => editor._clearDraftOptionDragState()}
            @keydown=${(event) => editor._handleDraftOptionHandleKeydown(event, optionIndex)}
            aria-label="Reorder option"
            title="Drag to reorder"
          >
            <div class="svg-icon size-4 icon-drag bg-stone-600"></div>
          </button>
          <input
            class="input-primary"
            data-question-modal-field
            type="text"
            maxlength="120"
            placeholder="Option"
            aria-label=${`Option ${optionIndex + 1}`}
            required
            .value=${option.label}
            ?disabled=${!editor._isModalOpen}
            @input=${(event) => editor._updateDraftOption(optionIndex, event.target.value)}
          />
          <button
            type="button"
            class="btn-tertiary px-2"
            ?disabled=${!editor._isModalOpen || editor._draftQuestion.options.length <= 1}
            @click=${() => editor._removeDraftOption(optionIndex)}
            aria-label="Remove option"
            title="Remove option"
          >
            <div class="svg-icon size-4 icon-trash bg-stone-500"></div>
          </button>
        </div>
      `,
    )}
  </div>
`;

export { renderQuestionsEditor };
