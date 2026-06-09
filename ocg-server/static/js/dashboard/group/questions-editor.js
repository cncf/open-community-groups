import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { closeModalBodyScroll, openModalBodyScroll } from "/static/js/common/modals/modal-lifecycle.js";
import { parseJsonAttribute } from "/static/js/common/utils.js";

const QUESTION_TYPES = [
  ["free-text", "Free text"],
  ["single-select", "Single select"],
  ["multi-select", "Multi select"],
];

const newId = () => crypto.randomUUID();

/**
 * Returns selectable options only for question types that support them.
 * @param {object|null|undefined} question Registration question payload
 * @returns {object[]} Question options, or an empty list for free text
 */
const normalizeQuestionOptions = (question) => {
  if (question?.kind === "free-text" || !Array.isArray(question?.options)) {
    return [];
  }

  return question.options;
};

/**
 * Normalizes registration questions loaded from template attributes or JS.
 * @param {*} questions Registration question payload
 * @returns {object[]} Normalized question list
 */
const normalizeQuestions = (questions) =>
  (Array.isArray(questions) ? questions : []).map((question) => ({
    id: question?.id || newId(),
    kind: question?.kind || "free-text",
    options: normalizeQuestionOptions(question),
    prompt: question?.prompt || "",
    required: question?.required === true,
  }));

const cloneQuestion = (question) => ({
  ...question,
  options: question.options.map((option) => ({ ...option })),
});

const createBlankQuestion = () => ({
  id: newId(),
  kind: "free-text",
  options: [],
  prompt: "",
  required: false,
});

/**
 * Renders the event registration questions editor and its form payload fields.
 * @extends LitWrapper
 */
class QuestionsEditor extends LitWrapper {
  static properties = {
    disabled: { type: Boolean, reflect: true },
    name: { type: String },
    questions: {
      attribute: "questions",
      converter: {
        fromAttribute(value) {
          return normalizeQuestions(parseJsonAttribute(value, []));
        },
      },
    },
    _draftQuestion: { state: true },
    _draggedOptionIndex: { state: true },
    _draggedQuestionIndex: { state: true },
    _dragOverOptionIndex: { state: true },
    _dragOverQuestionIndex: { state: true },
    _editingQuestionIndex: { state: true },
    _isModalOpen: { state: true },
    _isNewQuestion: { state: true },
  };

  constructor() {
    super();
    this.disabled = false;
    this.name = "questions";
    this._questions = [];
    this._draftQuestion = null;
    this._draggedOptionIndex = null;
    this._draggedQuestionIndex = null;
    this._dragOverOptionIndex = null;
    this._dragOverQuestionIndex = null;
    this._editingQuestionIndex = null;
    this._isModalOpen = false;
    this._isNewQuestion = false;
  }

  disconnectedCallback() {
    this._isModalOpen = closeModalBodyScroll(this._isModalOpen);

    super.disconnectedCallback();
  }

  get questions() {
    return this._questions;
  }

  set questions(value) {
    const previousQuestions = this._questions;
    this._questions = normalizeQuestions(value);
    this.requestUpdate("questions", previousQuestions);
  }

  /**
   * Adds a blank free-text question.
   * @returns {void}
   */
  _addQuestion() {
    this._openQuestionModal();
  }

  /**
   * Adds a blank option to the draft question.
   * @returns {void}
   */
  _addDraftOption() {
    this._updateDraftQuestion({
      options: [...this._draftQuestion.options, { id: newId(), label: "" }],
    });
  }

  /**
   * Closes the modal and clears draft state.
   * @returns {void}
   */
  _closeQuestionModal() {
    if (!this._isModalOpen) {
      return;
    }

    this._draftQuestion = null;
    this._draggedOptionIndex = null;
    this._dragOverOptionIndex = null;
    this._editingQuestionIndex = null;
    const wasOpen = this._isModalOpen;
    this._isNewQuestion = false;
    this._isModalOpen = closeModalBodyScroll(wasOpen);
  }

  /**
   * Returns the label for a question type value.
   * @param {string} kind Question kind
   * @returns {string} Human-readable label
   */
  _getQuestionTypeLabel(kind) {
    return QUESTION_TYPES.find(([value]) => value === kind)?.[1] || "Free text";
  }

  /**
   * Opens the add or edit modal.
   * @param {number|null} [questionIndex=null] Existing question index
   * @returns {void}
   */
  _openQuestionModal(questionIndex = null) {
    if (this.disabled) {
      return;
    }

    const existingQuestion = questionIndex === null ? null : this.questions[questionIndex];
    this._draftQuestion = existingQuestion ? cloneQuestion(existingQuestion) : createBlankQuestion();
    this._editingQuestionIndex = questionIndex;
    this._isNewQuestion = questionIndex === null;
    this._isModalOpen = openModalBodyScroll(this._isModalOpen);
    this.updateComplete.then(() => this.querySelector("[data-question-modal-field]")?.focus());
  }

  /**
   * Removes one option from the draft question.
   * @param {number} optionIndex Option index
   * @returns {void}
   */
  _removeDraftOption(optionIndex) {
    if (this._draftQuestion.options.length <= 1) {
      return;
    }

    this._updateDraftQuestion({
      options: this._draftQuestion.options.filter((_, index) => index !== optionIndex),
    });
  }

  /**
   * Moves a draft option up or down in the list.
   * @param {number} optionIndex Option index
   * @param {number} direction Movement direction
   * @returns {void}
   */
  _moveDraftOption(optionIndex, direction) {
    const targetIndex = optionIndex + direction;
    if (targetIndex < 0 || targetIndex >= this._draftQuestion.options.length) {
      return;
    }

    this._reorderDraftOptions(optionIndex, targetIndex);
  }

  /**
   * Reorders draft options.
   * @param {number} sourceIndex Source option index
   * @param {number} targetIndex Target option index
   * @returns {void}
   */
  _reorderDraftOptions(sourceIndex, targetIndex) {
    if (sourceIndex === targetIndex) {
      return;
    }

    const options = [...this._draftQuestion.options];
    const [option] = options.splice(sourceIndex, 1);
    options.splice(targetIndex, 0, option);
    this._updateDraftQuestion({ options });
  }

  /**
   * Clears draft option drag state.
   * @returns {void}
   */
  _clearDraftOptionDragState() {
    this._draggedOptionIndex = null;
    this._dragOverOptionIndex = null;
    this.requestUpdate();
  }

  /**
   * Starts dragging a draft option.
   * @param {DragEvent} event Drag event
   * @param {number} optionIndex Option index
   * @returns {void}
   */
  _handleDraftOptionDragStart(event, optionIndex) {
    this._draggedOptionIndex = optionIndex;
    this._dragOverOptionIndex = optionIndex;
    if (event.dataTransfer) {
      event.dataTransfer.effectAllowed = "move";
      event.dataTransfer.setData("text/plain", String(optionIndex));
      event.dataTransfer.setDragImage(event.currentTarget, 0, 0);
    }
  }

  /**
   * Tracks the current draft option drop target.
   * @param {DragEvent} event Drag event
   * @param {number} optionIndex Option index
   * @returns {void}
   */
  _handleDraftOptionDragOver(event, optionIndex) {
    event.preventDefault();
    if (this._draggedOptionIndex === null) {
      return;
    }

    this._dragOverOptionIndex = optionIndex;
  }

  /**
   * Clears drag-over state after leaving an option row.
   * @param {number} optionIndex Option index
   * @returns {void}
   */
  _handleDraftOptionDragLeave(optionIndex) {
    if (this._dragOverOptionIndex === optionIndex) {
      this._dragOverOptionIndex = null;
    }
  }

  /**
   * Reorders draft options when one is dropped.
   * @param {DragEvent} event Drag event
   * @param {number} optionIndex Option index
   * @returns {void}
   */
  _handleDraftOptionDrop(event, optionIndex) {
    event.preventDefault();
    if (this._draggedOptionIndex === null) {
      return;
    }

    this._reorderDraftOptions(this._draggedOptionIndex, optionIndex);
    this._clearDraftOptionDragState();
  }

  /**
   * Handles keyboard reordering from the draft option handle.
   * @param {KeyboardEvent} event Keyboard event
   * @param {number} optionIndex Option index
   * @returns {void}
   */
  _handleDraftOptionHandleKeydown(event, optionIndex) {
    if (event.key === "ArrowUp") {
      event.preventDefault();
      this._moveDraftOption(optionIndex, -1);
    } else if (event.key === "ArrowDown") {
      event.preventDefault();
      this._moveDraftOption(optionIndex, 1);
    }
  }

  /**
   * Moves a question up or down in the list.
   * @param {number} questionIndex Question index
   * @param {number} direction Movement direction
   * @returns {void}
   */
  _moveQuestion(questionIndex, direction) {
    if (this.disabled) {
      return;
    }

    const targetIndex = questionIndex + direction;
    if (targetIndex < 0 || targetIndex >= this.questions.length) {
      return;
    }

    this._reorderQuestions(questionIndex, targetIndex);
  }

  /**
   * Reorders questions.
   * @param {number} sourceIndex Source question index
   * @param {number} targetIndex Target question index
   * @returns {void}
   */
  _reorderQuestions(sourceIndex, targetIndex) {
    if (this.disabled || sourceIndex === targetIndex) {
      return;
    }

    const questions = [...this.questions];
    const [question] = questions.splice(sourceIndex, 1);
    questions.splice(targetIndex, 0, question);
    this.questions = questions;
  }

  /**
   * Clears question drag state.
   * @returns {void}
   */
  _clearQuestionDragState() {
    this._draggedQuestionIndex = null;
    this._dragOverQuestionIndex = null;
    this.requestUpdate();
  }

  /**
   * Starts dragging a question.
   * @param {DragEvent} event Drag event
   * @param {number} questionIndex Question index
   * @returns {void}
   */
  _handleQuestionDragStart(event, questionIndex) {
    if (this.disabled || this.questions.length <= 1) {
      event.preventDefault();
      return;
    }

    this._draggedQuestionIndex = questionIndex;
    this._dragOverQuestionIndex = questionIndex;
    if (event.dataTransfer) {
      event.dataTransfer.effectAllowed = "move";
      event.dataTransfer.setData("text/plain", String(questionIndex));
      event.dataTransfer.setDragImage(event.currentTarget, 0, 0);
    }
  }

  /**
   * Tracks the current question drop target.
   * @param {DragEvent} event Drag event
   * @param {number} questionIndex Question index
   * @returns {void}
   */
  _handleQuestionDragOver(event, questionIndex) {
    if (this.disabled) {
      return;
    }

    event.preventDefault();
    if (this._draggedQuestionIndex === null) {
      return;
    }

    this._dragOverQuestionIndex = questionIndex;
  }

  /**
   * Clears drag-over state after leaving a question row.
   * @param {number} questionIndex Question index
   * @returns {void}
   */
  _handleQuestionDragLeave(questionIndex) {
    if (this._dragOverQuestionIndex === questionIndex) {
      this._dragOverQuestionIndex = null;
    }
  }

  /**
   * Reorders questions when one is dropped.
   * @param {DragEvent} event Drag event
   * @param {number} questionIndex Question index
   * @returns {void}
   */
  _handleQuestionDrop(event, questionIndex) {
    if (this.disabled) {
      return;
    }

    event.preventDefault();
    if (this._draggedQuestionIndex === null) {
      return;
    }

    this._reorderQuestions(this._draggedQuestionIndex, questionIndex);
    this._clearQuestionDragState();
  }

  /**
   * Handles keyboard reordering from the question handle.
   * @param {KeyboardEvent} event Keyboard event
   * @param {number} questionIndex Question index
   * @returns {void}
   */
  _handleQuestionHandleKeydown(event, questionIndex) {
    if (this.disabled) {
      return;
    }

    if (event.key === "ArrowUp") {
      event.preventDefault();
      this._moveQuestion(questionIndex, -1);
    } else if (event.key === "ArrowDown") {
      event.preventDefault();
      this._moveQuestion(questionIndex, 1);
    }
  }

  /**
   * Removes a question from the editor.
   * @param {number} questionIndex Question index
   * @returns {void}
   */
  _removeQuestion(questionIndex) {
    this.questions = this.questions.filter((_, index) => index !== questionIndex);
  }

  /**
   * Saves the draft question to the editor list.
   * @returns {void}
   */
  _saveQuestion() {
    const invalidField = Array.from(this.querySelectorAll("[data-question-modal-field]")).find(
      (field) => !field.checkValidity(),
    );

    if (invalidField) {
      invalidField.reportValidity();
      invalidField.focus();
      return;
    }

    const question = {
      ...this._draftQuestion,
      options: normalizeQuestionOptions(this._draftQuestion),
      prompt: this._draftQuestion.prompt.trim(),
    };

    if (this._isNewQuestion) {
      this.questions = [...this.questions, question];
    } else {
      this.questions = this.questions.map((existingQuestion, index) =>
        index === this._editingQuestionIndex ? question : existingQuestion,
      );
    }

    this._closeQuestionModal();
  }

  /**
   * Updates the draft option label.
   * @param {number} optionIndex Option index
   * @param {string} label Option label
   * @returns {void}
   */
  _updateDraftOption(optionIndex, label) {
    const options = this._draftQuestion.options.map((option, index) =>
      index === optionIndex ? { ...option, label } : option,
    );
    this._updateDraftQuestion({ options });
  }

  /**
   * Updates the draft question while keeping options aligned with the type.
   * @param {object} changes Question changes
   * @returns {void}
   */
  _updateDraftQuestion(changes) {
    const next = { ...this._draftQuestion, ...changes };
    if (changes.kind === "free-text") {
      next.options = [];
    } else if (changes.kind && next.options.length === 0) {
      next.options = [{ id: newId(), label: "" }];
    }
    this._draftQuestion = next;
  }

  /**
   * Renders the complete editor.
   * @returns {unknown} Lit template
   */
  render() {
    return html`
      ${this._renderHiddenFields()}
      <div class="w-full space-y-8">
        ${this.questions.length > 0 && !this.disabled ? this._renderQuestionEditingWarning() : ""}
        <div class="space-y-5">
          <div class="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
            <div class="text-sm font-semibold text-stone-700">
              ${this.questions.length} ${this.questions.length === 1 ? "question" : "questions"}
              <span class="mx-2 text-stone-400">•</span>
              ${this.questions.filter((question) => question.required).length} required
            </div>
            <button
              type="button"
              class="btn-primary-outline btn-mini inline-flex items-center justify-center gap-2"
              ?disabled=${this.disabled}
              @click=${this._addQuestion}
            >
              <div class="svg-icon size-4 icon-add-circle"></div>
              Add question
            </button>
          </div>

          <div class="mt-5 space-y-3">
            ${this.questions.length === 0
              ? this._renderEmptyState()
              : this.questions.map((question, questionIndex) =>
                  this._renderQuestionCard(question, questionIndex),
                )}
          </div>
        </div>
      </div>
      ${this._renderQuestionModal()}
    `;
  }

  /**
   * Renders the warning shown while registration questions can still be edited.
   * @returns {unknown} Lit template
   */
  _renderQuestionEditingWarning() {
    return html`
      <div
        data-question-editing-warning
        class="w-full rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900"
      >
        Questionnaire questions cannot be edited after an attendee has submitted answers.
      </div>
    `;
  }

  /**
   * Renders hidden inputs using the serde_qs payload structure.
   * @returns {unknown} Lit template
   */
  _renderHiddenFields() {
    return html`
      <input type="hidden" name="${this.name}_present" value="true" />
      ${this.questions.flatMap((question, questionIndex) => {
        const questionPrefix = `${this.name}[${questionIndex}]`;
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
  }

  /**
   * Renders the empty state.
   * @returns {unknown} Lit template
   */
  _renderEmptyState() {
    const message = this.disabled
      ? "No registration questions were added for this event."
      : 'No registration questions yet. Click "Add question" to create one.';

    return html`<div class="py-8 text-center text-sm italic text-stone-400">${message}</div>`;
  }

  /**
   * Renders a question card.
   * @param {object} question Question state
   * @param {number} questionIndex Question index
   * @returns {unknown} Lit template
   */
  _renderQuestionCard(question, questionIndex) {
    return html`
      <div
        class=${[
          "flex items-start gap-2",
          this._draggedQuestionIndex === questionIndex ? "opacity-70" : "",
        ].join(" ")}
        @dragover=${(event) => this._handleQuestionDragOver(event, questionIndex)}
        @dragleave=${() => this._handleQuestionDragLeave(questionIndex)}
        @drop=${(event) => this._handleQuestionDrop(event, questionIndex)}
      >
        <button
          type="button"
          class="shrink-0 rounded-full p-2 transition-colors hover:bg-stone-100 ${this.disabled ||
          this.questions.length <= 1
            ? "cursor-not-allowed opacity-60"
            : "cursor-grab active:cursor-grabbing"}"
          draggable=${this.disabled || this.questions.length <= 1 ? "false" : "true"}
          ?disabled=${this.disabled || this.questions.length <= 1}
          @dragstart=${(event) => this._handleQuestionDragStart(event, questionIndex)}
          @dragend=${() => this._clearQuestionDragState()}
          @keydown=${(event) => this._handleQuestionHandleKeydown(event, questionIndex)}
          aria-label="Reorder question"
          title="Drag to reorder"
        >
          <div class="svg-icon size-4 icon-drag bg-stone-600"></div>
        </button>
        <div
          class=${[
            "min-w-0 flex-1 rounded-md border border-stone-200 bg-white p-4",
            this._dragOverQuestionIndex === questionIndex &&
            this._draggedQuestionIndex !== null &&
            this._draggedQuestionIndex !== questionIndex
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
                    <span class="text-stone-500">${this._getQuestionTypeLabel(question.kind)}</span>
                    ${question.required
                      ? html`
                          <span class="text-stone-400">•</span>
                          <span class="font-medium text-stone-700">Required</span>
                        `
                      : ""}
                  </div>
                </div>

                <div class="flex shrink-0 items-center gap-1">
                  <button
                    type="button"
                    class="rounded-full p-2 transition-colors hover:bg-stone-100 ${this.disabled
                      ? "cursor-not-allowed opacity-60"
                      : ""}"
                    ?disabled=${this.disabled}
                    @click=${() => this._openQuestionModal(questionIndex)}
                    aria-label="Edit question"
                    title="Edit"
                  >
                    <div class="svg-icon size-4 icon-pencil bg-stone-600"></div>
                  </button>
                  <button
                    type="button"
                    class="rounded-full p-2 transition-colors hover:bg-stone-100 ${this.disabled
                      ? "cursor-not-allowed opacity-60"
                      : ""}"
                    ?disabled=${this.disabled}
                    @click=${() => this._removeQuestion(questionIndex)}
                    aria-label="Delete question"
                    title="Delete"
                  >
                    <div class="svg-icon size-4 icon-trash bg-stone-600"></div>
                  </button>
                </div>
              </div>
              ${question.options.length > 0 ? this._renderOptionPreview(question.options) : ""}
            </div>
          </div>
        </div>
      </div>
    `;
  }

  /**
   * Renders option preview badges for a question card.
   * @param {object[]} options Question options
   * @returns {unknown} Lit template
   */
  _renderOptionPreview(options) {
    return html`
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
  }

  /**
   * Renders the add/edit question modal.
   * @returns {unknown} Lit template
   */
  _renderQuestionModal() {
    return html`
      <div
        class="fixed inset-0 z-[1000] ${this._isModalOpen
          ? "flex"
          : "hidden"} items-center justify-center overflow-y-auto overflow-x-hidden"
        role="dialog"
        aria-modal="true"
        aria-labelledby="question-modal-title"
        data-pending-changes-ignore
      >
        <div
          class="absolute inset-0 bg-stone-950 opacity-35"
          @click=${() => this._closeQuestionModal()}
        ></div>
        <div class="modal-panel max-w-6xl p-4">
          <div class="modal-card rounded-lg">
            <div class="flex shrink-0 items-center justify-between border-b border-stone-200 p-5">
              <h3 id="question-modal-title" class="text-xl font-semibold text-stone-900">
                ${this._isNewQuestion ? "Add question" : "Edit question"}
              </h3>
              <button
                type="button"
                class="group inline-flex h-8 w-8 items-center justify-center rounded-lg bg-transparent text-sm text-stone-400 transition-colors hover:bg-stone-100"
                ?disabled=${!this._isModalOpen}
                @click=${() => this._closeQuestionModal()}
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
                    .value=${this._draftQuestion?.prompt || ""}
                    ?disabled=${!this._isModalOpen}
                    @input=${(event) => this._updateDraftQuestion({ prompt: event.target.value })}
                  />
                </div>
              </div>

              <div class="max-w-xs">
                <label class="form-label" for="question-kind-draft">Type</label>
                <div class="mt-2">
                  <select
                    id="question-kind-draft"
                    class="select-primary"
                    .value=${this._draftQuestion?.kind || "free-text"}
                    ?disabled=${!this._isModalOpen}
                    @change=${(event) => this._updateDraftQuestion({ kind: event.target.value })}
                  >
                    ${QUESTION_TYPES.map(
                      ([value, label]) =>
                        html`<option value=${value} ?selected=${this._draftQuestion?.kind === value}>
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
                  .checked=${this._draftQuestion?.required || false}
                  ?disabled=${!this._isModalOpen}
                  @change=${(event) => this._updateDraftQuestion({ required: event.target.checked })}
                />
                <div
                  class="relative h-6 w-11 rounded-full bg-stone-200 peer peer-checked:bg-primary-500 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-primary-300 after:absolute after:start-0.5 after:top-0.5 after:h-5 after:w-5 after:rounded-full after:border after:border-stone-200 after:bg-white after:transition-all after:content-[''] peer-checked:after:translate-x-full peer-checked:after:border-white rtl:peer-checked:after:-translate-x-full"
                ></div>
                <span class="ms-3 text-sm font-medium text-stone-900">Required</span>
              </label>

              ${this._draftQuestion && this._draftQuestion.kind !== "free-text"
                ? this._renderDraftOptions()
                : ""}
            </div>

            <div class="flex shrink-0 items-center justify-end gap-3 border-t border-stone-200 p-5">
              <button
                type="button"
                class="btn-secondary"
                ?disabled=${!this._isModalOpen}
                @click=${() => this._closeQuestionModal()}
              >
                Cancel
              </button>
              <button
                type="button"
                class="btn-primary"
                ?disabled=${!this._isModalOpen}
                @click=${() => this._saveQuestion()}
              >
                ${this._isNewQuestion ? "Add question" : "Save question"}
              </button>
            </div>
          </div>
        </div>
      </div>
    `;
  }

  /**
   * Renders option controls for the draft question.
   * @returns {unknown} Lit template
   */
  _renderDraftOptions() {
    return html`
      <div class="space-y-3">
        <div class="flex items-center justify-between gap-3">
          <div class="form-label">Options</div>
          <button
            type="button"
            class="btn-primary-outline btn-mini inline-flex items-center justify-center gap-2"
            ?disabled=${!this._isModalOpen}
            @click=${() => this._addDraftOption()}
          >
            <div class="svg-icon size-3 icon-add-circle"></div>
            Add option
          </button>
        </div>
        ${this._draftQuestion.options.map(
          (option, optionIndex) => html`
            <div
              class=${[
                "flex items-center gap-2 rounded-md",
                this._dragOverOptionIndex === optionIndex &&
                this._draggedOptionIndex !== null &&
                this._draggedOptionIndex !== optionIndex
                  ? "ring-2 ring-primary-300"
                  : "",
                this._draggedOptionIndex === optionIndex ? "opacity-70" : "",
              ].join(" ")}
              @dragover=${(event) => this._handleDraftOptionDragOver(event, optionIndex)}
              @dragleave=${() => this._handleDraftOptionDragLeave(optionIndex)}
              @drop=${(event) => this._handleDraftOptionDrop(event, optionIndex)}
            >
              <button
                type="button"
                class="shrink-0 rounded-full p-2 transition-colors hover:bg-stone-100 ${!this._isModalOpen ||
                this._draftQuestion.options.length <= 1
                  ? "cursor-not-allowed opacity-60"
                  : "cursor-grab active:cursor-grabbing"}"
                draggable="true"
                ?disabled=${!this._isModalOpen || this._draftQuestion.options.length <= 1}
                @dragstart=${(event) => this._handleDraftOptionDragStart(event, optionIndex)}
                @dragend=${() => this._clearDraftOptionDragState()}
                @keydown=${(event) => this._handleDraftOptionHandleKeydown(event, optionIndex)}
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
                ?disabled=${!this._isModalOpen}
                @input=${(event) => this._updateDraftOption(optionIndex, event.target.value)}
              />
              <button
                type="button"
                class="btn-tertiary px-2"
                ?disabled=${!this._isModalOpen || this._draftQuestion.options.length <= 1}
                @click=${() => this._removeDraftOption(optionIndex)}
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
  }
}

if (!customElements.get("questions-editor")) {
  customElements.define("questions-editor", QuestionsEditor);
}
