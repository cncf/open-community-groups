import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";

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
          if (!value) return [];
          try {
            return normalizeQuestions(JSON.parse(value));
          } catch {
            return [];
          }
        },
      },
    },
  };

  constructor() {
    super();
    this.disabled = false;
    this.name = "questions";
    this._questions = [];
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
    this.questions = [
      ...this.questions,
      {
        id: newId(),
        kind: "free-text",
        options: [],
        prompt: "",
        required: false,
      },
    ];
  }

  /**
   * Adds a blank option to a selectable question.
   * @param {number} questionIndex Question index
   * @returns {void}
   */
  _addOption(questionIndex) {
    this._updateQuestion(questionIndex, {
      options: [...this.questions[questionIndex].options, { id: newId(), label: "" }],
    });
  }

  /**
   * Removes one option from a selectable question.
   * @param {number} questionIndex Question index
   * @param {number} optionIndex Option index
   * @returns {void}
   */
  _removeOption(questionIndex, optionIndex) {
    const question = this.questions[questionIndex];
    if (question.options.length <= 1) {
      return;
    }

    this._updateQuestion(questionIndex, {
      options: question.options.filter((_, index) => index !== optionIndex),
    });
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
   * Updates the visible label for one selectable option.
   * @param {number} questionIndex Question index
   * @param {number} optionIndex Option index
   * @param {string} label Option label
   * @returns {void}
   */
  _updateOption(questionIndex, optionIndex, label) {
    const question = this.questions[questionIndex];
    const options = question.options.map((option, index) =>
      index === optionIndex ? { ...option, label } : option,
    );
    this._updateQuestion(questionIndex, { options });
  }

  /**
   * Updates a question while keeping options aligned with the selected type.
   * @param {number} questionIndex Question index
   * @param {object} changes Question changes
   * @returns {void}
   */
  _updateQuestion(questionIndex, changes) {
    this.questions = this.questions.map((question, index) => {
      if (index !== questionIndex) {
        return question;
      }

      const next = { ...question, ...changes };
      if (changes.kind === "free-text") {
        next.options = [];
      } else if (changes.kind && next.options.length === 0) {
        next.options = [{ id: newId(), label: "" }];
      }
      return next;
    });
  }

  /**
   * Renders the complete editor.
   * @returns {unknown} Lit template
   */
  render() {
    return html`
      ${this._renderHiddenFields()}
      <div class="w-full space-y-4">
        ${this.questions.length > 0 && !this.disabled ? this._renderQuestionEditingWarning() : ""}
        <div class="max-w-5xl space-y-4">
          ${this.questions.map((question, questionIndex) => this._renderQuestion(question, questionIndex))}
          <button
            type="button"
            class="btn-primary-outline"
            ?disabled=${this.disabled}
            @click=${this._addQuestion}
          >
            Add question
          </button>
        </div>
      </div>
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
   * Renders a question card.
   * @param {object} question Question state
   * @param {number} questionIndex Question index
   * @returns {unknown} Lit template
   */
  _renderQuestion(question, questionIndex) {
    return html`
      <div class="rounded-md border border-stone-200 bg-white p-4">
        <div class="grid gap-4 md:grid-cols-[minmax(0,1fr)_12rem_auto]">
          <div>
            <label class="form-label" for="question-${question.id}">Question</label>
            <input
              id="question-${question.id}"
              class="input-primary mt-2"
              type="text"
              maxlength="500"
              required
              .value=${question.prompt}
              ?disabled=${this.disabled}
              @input=${(event) => this._updateQuestion(questionIndex, { prompt: event.target.value })}
            />
          </div>
          <div>
            <label class="form-label" for="question-kind-${question.id}">Type</label>
            <select
              id="question-kind-${question.id}"
              class="select-primary mt-2"
              .value=${question.kind}
              ?disabled=${this.disabled}
              @change=${(event) => this._updateQuestion(questionIndex, { kind: event.target.value })}
            >
              ${QUESTION_TYPES.map(
                ([value, label]) =>
                  html`<option value=${value} ?selected=${question.kind === value}>${label}</option>`,
              )}
            </select>
          </div>
          <div class="flex items-end gap-3">
            <label class="mb-2 inline-flex items-center gap-2 text-sm font-medium text-stone-900">
              <input
                type="checkbox"
                class="checkbox-primary"
                .checked=${question.required}
                ?disabled=${this.disabled}
                @change=${(event) => this._updateQuestion(questionIndex, { required: event.target.checked })}
              />
              Required
            </label>
            <button
              type="button"
              class="btn-tertiary mb-1"
              ?disabled=${this.disabled}
              @click=${() => this._removeQuestion(questionIndex)}
              aria-label="Remove question"
              title="Remove question"
            >
              <div class="svg-icon size-4 icon-trash bg-stone-500"></div>
            </button>
          </div>
        </div>
        ${question.kind === "free-text" ? "" : this._renderOptions(question, questionIndex)}
      </div>
    `;
  }

  /**
   * Renders option controls for a selectable question.
   * @param {object} question Question state
   * @param {number} questionIndex Question index
   * @returns {unknown} Lit template
   */
  _renderOptions(question, questionIndex) {
    return html`
      <div class="mt-4 space-y-3 border-t border-stone-100 pt-4">
        ${question.options.map(
          (option, optionIndex) => html`
            <div class="flex gap-2">
              <input
                class="input-primary"
                type="text"
                maxlength="120"
                placeholder="Option"
                aria-label=${`Option ${optionIndex + 1}`}
                required
                .value=${option.label}
                ?disabled=${this.disabled}
                @input=${(event) => this._updateOption(questionIndex, optionIndex, event.target.value)}
              />
              <button
                type="button"
                class="btn-tertiary"
                ?disabled=${this.disabled || question.options.length <= 1}
                @click=${() => this._removeOption(questionIndex, optionIndex)}
                aria-label="Remove option"
                title="Remove option"
              >
                <div class="svg-icon size-4 icon-trash bg-stone-500"></div>
              </button>
            </div>
          `,
        )}
        <button
          type="button"
          class="btn-primary-outline btn-mini"
          ?disabled=${this.disabled}
          @click=${() => this._addOption(questionIndex)}
        >
          Add option
        </button>
      </div>
    `;
  }
}

customElements.define("questions-editor", QuestionsEditor);
