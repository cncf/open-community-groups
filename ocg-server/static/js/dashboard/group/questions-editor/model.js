const QUESTION_TYPES = [
  ["free-text", "Free text"],
  ["single-select", "Single select"],
  ["multi-select", "Multi select"],
];

const newQuestionId = () => crypto.randomUUID();

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
    id: question?.id || newQuestionId(),
    kind: question?.kind || "free-text",
    options: normalizeQuestionOptions(question),
    prompt: question?.prompt || "",
    required: question?.required === true,
  }));

/**
 * Clones a question and its option list before editing.
 * @param {object} question Question state
 * @returns {object} Cloned question state
 */
const cloneQuestion = (question) => ({
  ...question,
  options: question.options.map((option) => ({ ...option })),
});

/**
 * Creates the default draft state for a new question.
 * @returns {object} Blank question state
 */
const createBlankQuestion = () => ({
  id: newQuestionId(),
  kind: "free-text",
  options: [],
  prompt: "",
  required: false,
});

/**
 * Creates the default draft state for a new selectable option.
 * @returns {object} Blank option state
 */
const createBlankQuestionOption = () => ({
  id: newQuestionId(),
  label: "",
});

/**
 * Returns the label for a question type value.
 * @param {string} kind Question kind
 * @returns {string} Human-readable label
 */
const getQuestionTypeLabel = (kind) => QUESTION_TYPES.find(([value]) => value === kind)?.[1] || "Free text";

export {
  QUESTION_TYPES,
  cloneQuestion,
  createBlankQuestion,
  createBlankQuestionOption,
  getQuestionTypeLabel,
  normalizeQuestionOptions,
  normalizeQuestions,
};
