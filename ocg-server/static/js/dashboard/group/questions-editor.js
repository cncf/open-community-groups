import { LitWrapper } from "/static/js/common/lit-wrapper.js";
import { closeModalBodyScroll, openModalBodyScroll } from "/static/js/common/modals/modal-lifecycle.js";
import { parseJsonAttribute } from "/static/js/common/utils.js";
import {
  cloneQuestion,
  createBlankQuestion,
  createBlankQuestionOption,
  normalizeQuestionOptions,
  normalizeQuestions,
} from "/static/js/dashboard/group/questions-editor/model.js";
import { renderQuestionsEditor } from "/static/js/dashboard/group/questions-editor/render.js";

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

    this._draftQuestion = null;
    this._draggedOptionIndex = null;
    this._dragOverOptionIndex = null;
    this._editingQuestionIndex = null;
    const wasOpen = this._isModalOpen;
    this._isNewQuestion = false;
    this._isModalOpen = closeModalBodyScroll(wasOpen);
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
