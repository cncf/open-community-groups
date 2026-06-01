const DEFAULT_FREE_TEXT_MESSAGE = "Answer this question.";
const DEFAULT_MULTI_SELECT_MESSAGE = "Select at least one option.";

const isAnswerControl = (control) =>
  control instanceof HTMLInputElement ||
  control instanceof HTMLTextAreaElement ||
  control instanceof HTMLSelectElement;

const clearQuestionValidity = (form, answerSelector) => {
  form.querySelectorAll(answerSelector).forEach((control) => {
    if (isAnswerControl(control)) {
      control.setCustomValidity("");
    }
  });
};

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
