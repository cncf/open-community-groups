import { isEscapeEvent } from "/static/js/common/keyboard.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import {
  bindModalDismissListeners,
  closeModalBodyScroll,
  focusModal,
  openModalBodyScroll,
  restoreModalFocus,
  trapModalFocus,
} from "/static/js/common/modals/modal-lifecycle.js";
import { parseJsonAttribute } from "/static/js/common/utils.js";
import {
  buildQuestionsEditorIdPrefix,
  buildQuestionsEditorIds,
  cloneQuestion,
  createBlankQuestion,
  createBlankQuestionOption,
  normalizePositiveInteger,
  normalizeQuestionOptions,
  normalizeQuestions,
} from "/static/js/dashboard/group/questions-editor/model.js";
import { renderQuestionsEditor } from "/static/js/dashboard/group/questions-editor/render.js";

/** Default warning shown while questions can still be edited. */
const DEFAULT_EDITING_WARNING = "Questions cannot be edited after answers have been submitted.";

/** Default empty-state message of a disabled editor. */
const DEFAULT_EMPTY_DISABLED_MESSAGE = "No questions were added.";

/** Default empty-state message of an editable editor. */
const DEFAULT_EMPTY_MESSAGE = 'No questions yet. Click "Add question" to create one.';

/** Default maximum option label length. */
const DEFAULT_OPTION_MAX_LENGTH = 120;

/** Default maximum question prompt length. */
const DEFAULT_PROMPT_MAX_LENGTH = 500;

/** Default help text of the Required toggle. */
const DEFAULT_REQUIRED_HELP = "Required questions must be answered. Optional questions can be skipped.";

/** Number of editors that generated their own id prefix. */
let generatedIdPrefixCount = 0;

/**
 * Renders a questionnaire questions editor and its form payload fields. Several
 * editors can share a page; each one renders its own element ids.
 * @extends LitWrapper
 */
class QuestionsEditor extends LitWrapper {
  static properties = {
    disabled: { type: Boolean, reflect: true },
    editingWarning: { type: String, attribute: "editing-warning" },
    emptyDisabledMessage: { type: String, attribute: "empty-disabled-message" },
    emptyMessage: { type: String, attribute: "empty-message" },
    maxQuestions: { type: Number, attribute: "max-questions" },
    name: { type: String },
    optionMaxLength: { type: Number, attribute: "option-max-length" },
    promptMaxLength: { type: Number, attribute: "prompt-max-length" },
    questions: {
      attribute: "questions",
      converter: {
        fromAttribute(value) {
          return normalizeQuestions(parseJsonAttribute(value, []));
        },
      },
    },
    requiredHelp: { type: String, attribute: "required-help" },
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
    this.editingWarning = DEFAULT_EDITING_WARNING;
    this.emptyDisabledMessage = DEFAULT_EMPTY_DISABLED_MESSAGE;
    this.emptyMessage = DEFAULT_EMPTY_MESSAGE;
    this.maxQuestions = null;
    this.name = "questions";
    this.optionMaxLength = DEFAULT_OPTION_MAX_LENGTH;
    this.promptMaxLength = DEFAULT_PROMPT_MAX_LENGTH;
    this.requiredHelp = DEFAULT_REQUIRED_HELP;
    this._questions = [];
    this._draftQuestion = null;
    this._draggedOptionIndex = null;
    this._draggedQuestionIndex = null;
    this._dragOverOptionIndex = null;
    this._dragOverQuestionIndex = null;
    this._editingQuestionIndex = null;
    this._isModalOpen = false;
    this._isNewQuestion = false;
    this._generatedIdPrefix = "";
    this._handleKeydown = this._handleKeydown.bind(this);
    this._ids = null;
    this._removeDismissListeners = null;
  }

  /**
   * Releases modal listeners, scroll lock and focus when detached.
   */
  disconnectedCallback() {
    const modal = this._resolveQuestionModal();
    const wasModalOpen = this._isModalOpen;
    this._unbindModalDismissListeners();
    this._isModalOpen = closeModalBodyScroll(this._isModalOpen);
    if (wasModalOpen) {
      restoreModalFocus(modal);
    }

    super.disconnectedCallback();
  }

  /**
   * Gets the element ids of this editor instance.
   * @returns {ReturnType<typeof buildQuestionsEditorIds>}
   */
  get ids() {
    if (!this.id && !this._generatedIdPrefix) {
      generatedIdPrefixCount += 1;
      this._generatedIdPrefix = buildQuestionsEditorIdPrefix(this.name, generatedIdPrefixCount);
    }

    const prefix = this.id || this._generatedIdPrefix;
    if (this._ids?.prefix !== prefix) {
      this._ids = { ...buildQuestionsEditorIds(prefix), prefix };
    }
    return this._ids;
  }

  /**
   * Gets the normalized length and count limits of the editor.
   * @returns {{optionMaxLength: number, promptMaxLength: number, questions: number|null}}
   */
  get limits() {
    return {
      optionMaxLength: normalizePositiveInteger(this.optionMaxLength, DEFAULT_OPTION_MAX_LENGTH),
      promptMaxLength: normalizePositiveInteger(this.promptMaxLength, DEFAULT_PROMPT_MAX_LENGTH),
      questions: normalizePositiveInteger(this.maxQuestions),
    };
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
   * Checks whether the question limit has been reached.
   * @returns {boolean}
   */
  get questionsLimitReached() {
    const limit = this.limits.questions;
    return limit !== null && this.questions.length >= limit;
  }

  /**
   * Adds a blank free-text question.
   * @param {HTMLElement|null} [trigger=null] Element that opened the modal
   * @returns {void}
   */
  _addQuestion(trigger = null) {
    if (this.questionsLimitReached) {
      return;
    }

    this._openQuestionModal(null, trigger);
  }

  /**
   * Adds a blank option to the draft question.
   * @returns {void}
   */
  _addDraftOption() {
    this._updateDraftQuestion({
      options: [...this._draftQuestion.options, createBlankQuestionOption()],
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

    const modal = this._resolveQuestionModal();
    this._draftQuestion = null;
    this._draggedOptionIndex = null;
    this._dragOverOptionIndex = null;
    this._editingQuestionIndex = null;
    const wasOpen = this._isModalOpen;
    this._isNewQuestion = false;
    this._isModalOpen = closeModalBodyScroll(wasOpen);
    this._unbindModalDismissListeners();
    this.updateComplete.then(() => {
      if (!this._isModalOpen) {
        restoreModalFocus(modal);
      }
    });
  }

  /**
   * Closes the modal on Escape and keeps Tab navigation inside it.
   * @param {KeyboardEvent} event Keyboard event
   * @returns {void}
   */
  _handleKeydown(event) {
    if (!this._isModalOpen) {
      return;
    }

    if (event.key === "Tab") {
      trapModalFocus(event, this._resolveQuestionModal());
      return;
    }

    if (isEscapeEvent(event)) {
      this._closeQuestionModal();
    }
  }

  /**
   * Opens the add or edit modal and moves focus inside it.
   * @param {number|null} [questionIndex=null] Existing question index
   * @param {HTMLElement|null} [trigger=null] Element that opened the modal
   * @returns {void}
   */
  _openQuestionModal(questionIndex = null, trigger = null) {
    if (this.disabled || this._isModalOpen) {
      return;
    }

    const ownerDocument = this.ownerDocument || document;
    const activeElement = ownerDocument.activeElement;
    const focusOrigin =
      trigger instanceof HTMLElement ? trigger : activeElement instanceof HTMLElement ? activeElement : null;
    const existingQuestion = questionIndex === null ? null : this.questions[questionIndex];
    this._draftQuestion = existingQuestion ? cloneQuestion(existingQuestion) : createBlankQuestion();
    this._editingQuestionIndex = questionIndex;
    this._isNewQuestion = questionIndex === null;
    this._isModalOpen = openModalBodyScroll(this._isModalOpen);
    this._removeDismissListeners = bindModalDismissListeners({
      onKeydown: this._handleKeydown,
      target: ownerDocument,
    });
    this.updateComplete.then(() => {
      if (this._isModalOpen && this.isConnected) {
        focusModal(this._resolveQuestionModal(), focusOrigin);
      }
    });
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
   * Resolves the question modal rendered by this editor.
   * @returns {Element|null}
   */
  _resolveQuestionModal() {
    return this.querySelector("[data-question-modal]");
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
   * Removes the modal keyboard listeners.
   * @returns {void}
   */
  _unbindModalDismissListeners() {
    this._removeDismissListeners?.();
    this._removeDismissListeners = null;
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
      next.options = [createBlankQuestionOption()];
    }
    this._draftQuestion = next;
  }

  /**
   * Renders the complete editor.
   * @returns {unknown} Lit template
   */
  render() {
    return renderQuestionsEditor(this);
  }
}

if (!customElements.get("questions-editor")) {
  customElements.define("questions-editor", QuestionsEditor);
}
