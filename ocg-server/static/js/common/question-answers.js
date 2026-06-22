const DEFAULT_FREE_TEXT_MESSAGE = "Answer this question.";
const DEFAULT_MULTI_SELECT_MESSAGE = "Select at least one option.";
const questionValidityRefreshers = new WeakMap();

/**
 * Checks whether a DOM node can hold a questionnaire answer value.
 * @param {Element|null} control Potential answer control.
 * @returns {boolean} Whether the node is a supported answer control.
 */
const isAnswerControl = (control) =>
  control instanceof HTMLInputElement ||
  control instanceof HTMLTextAreaElement ||
  control instanceof HTMLSelectElement;

/**
 * Clears custom validity from every answer control in a root element.
 * @param {Element|HTMLFormElement} root Questions root element.
 * @param {string} answerSelector Selector for answer controls.
 * @returns {void}
 */
const clearQuestionValidity = (root, answerSelector) => {
  root.querySelectorAll(answerSelector).forEach((control) => {
    if (isAnswerControl(control)) {
      control.setCustomValidity("");
    }
  });
};

/**
 * Checks whether a required question has a complete answer.
 * @param {HTMLFieldSetElement} fieldset Question fieldset.
 * @param {string} answerSelector Selector for answer controls.
 * @returns {boolean} Whether the question has a valid answer.
 */
const hasRequiredQuestionAnswer = (fieldset, answerSelector) => {
  if (fieldset.dataset.questionKind === "free-text") {
    const input = fieldset.querySelector(answerSelector);
    return input instanceof HTMLTextAreaElement && input.value.trim().length > 0;
  }

  return fieldset.querySelector(`${answerSelector}:checked`) instanceof HTMLInputElement;
};

/**
 * Clears stale custom validity once an invalid question becomes complete.
 * @param {HTMLFieldSetElement} fieldset Question fieldset.
 * @param {string} answerSelector Selector for answer controls.
 * @returns {void}
 */
const bindQuestionValidityRefresh = (fieldset, answerSelector) => {
  if (questionValidityRefreshers.has(fieldset)) {
    return;
  }

  const refreshValidity = () => {
    if (hasRequiredQuestionAnswer(fieldset, answerSelector)) {
      clearQuestionValidity(fieldset, answerSelector);
    }
  };

  fieldset.addEventListener("input", refreshValidity);
  fieldset.addEventListener("change", refreshValidity);
  questionValidityRefreshers.set(fieldset, refreshValidity);
};

/**
 * Sets custom validity on the first answer control inside a question fieldset.
 * @param {HTMLFieldSetElement} fieldset Question fieldset.
 * @param {string} answerSelector Selector for answer controls.
 * @param {string} message Custom validity message.
 * @returns {void}
 */
const setQuestionValidity = (fieldset, answerSelector, message) => {
  const control = fieldset.querySelector(answerSelector);
  if (isAnswerControl(control)) {
    control.setCustomValidity(message);
  }
};

/**
 * @typedef {object} QuestionAnswersPayload
 * @property {{question_id: string, value: string|string[]}[]} answers Collected answers
 */

/**
 * Collects and validates questionnaire answers from fieldset-based markup.
 * @param {HTMLFormElement} form Questions form
 * @param {object} config Collector config
 * @param {string} config.answerSelector Selector for answer controls
 * @returns {QuestionAnswersPayload|null} Answers payload, or null when invalid
 */
export const collectQuestionAnswers = (form, { answerSelector }) => {
  clearQuestionValidity(form, answerSelector);
  const answers = [];

  form.querySelectorAll("[data-question-id]").forEach((fieldset) => {
    if (!(fieldset instanceof HTMLFieldSetElement)) {
      return;
    }

    const questionId = fieldset.dataset.questionId;
    const kind = fieldset.dataset.questionKind;
    const required = fieldset.dataset.questionRequired === "true";
    if (!questionId || !kind) {
      return;
    }

    if (kind === "free-text") {
      const input = fieldset.querySelector(answerSelector);
      if (!(input instanceof HTMLTextAreaElement)) {
        return;
      }

      const value = input.value.trim();
      if (required && !value) {
        input.setCustomValidity(DEFAULT_FREE_TEXT_MESSAGE);
        bindQuestionValidityRefresh(fieldset, answerSelector);
      }
      if (value || required) {
        answers.push({ question_id: questionId, value });
      }
      return;
    }

    if (kind === "single-select") {
      const selected = fieldset.querySelector(`${answerSelector}:checked`);
      if (selected instanceof HTMLInputElement) {
        answers.push({ question_id: questionId, value: selected.value });
      }
      return;
    }

    const values = Array.from(fieldset.querySelectorAll(`${answerSelector}:checked`))
      .filter((input) => input instanceof HTMLInputElement)
      .map((input) => input.value);
    if (values.length > 0 || required) {
      answers.push({ question_id: questionId, value: values });
    }
    if (required && values.length === 0) {
      setQuestionValidity(fieldset, answerSelector, DEFAULT_MULTI_SELECT_MESSAGE);
      bindQuestionValidityRefresh(fieldset, answerSelector);
    }
  });

  return form.reportValidity() ? { answers } : null;
};

/**
 * Serializes an answer payload into a hidden form input.
 * @param {HTMLFormElement} form Questions form
 * @param {string} inputSelector Hidden input selector
 * @param {QuestionAnswersPayload} answersPayload Answers payload
 * @returns {boolean} Whether an input was updated
 */
export const setQuestionAnswersInputValue = (form, inputSelector, answersPayload) => {
  const input = form.querySelector(inputSelector);
  if (!(input instanceof HTMLInputElement)) {
    return false;
  }

  input.value = JSON.stringify(answersPayload);
  return true;
};
