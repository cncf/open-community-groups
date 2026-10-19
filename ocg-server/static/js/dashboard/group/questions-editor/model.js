const QUESTION_TYPES = [
  ["free-text", "Free text"],
  ["single-select", "Single select"],
  ["multi-select", "Multi select"],
];

/**
 * Builds the element ids of one questions editor instance, so several editors
 * can share a page without colliding ids.
 * @param {string} prefix Instance id prefix
 * @returns {{
 *   kind: string,
 *   limit: string,
 *   modalTitle: string,
 *   option: (optionId: string) => string,
 *   options: string,
 *   prompt: string,
 *   required: string,
 *   requiredHelp: string
 * }} Instance element ids
 */
const buildQuestionsEditorIds = (prefix) => ({
  kind: `${prefix}-kind`,
  limit: `${prefix}-limit`,
  modalTitle: `${prefix}-modal-title`,
  option: (optionId) => `${prefix}-option-${sanitizeIdPart(optionId)}`,
  options: `${prefix}-options`,
  prompt: `${prefix}-prompt`,
  required: `${prefix}-required`,
  requiredHelp: `${prefix}-required-help`,
});

/**
 * Builds the id prefix of a questions editor instance.
 * @param {string} name Payload field name of the editor
 * @param {number} sequence Instance sequence number
 * @returns {string} Instance id prefix
 */
const buildQuestionsEditorIdPrefix = (name, sequence) =>
  `questions-editor-${sanitizeIdPart(name) || "questions"}-${sequence}`;

/**
 * Creates a stable client-side id for draft questions and options.
 * @returns {string} Unique draft identifier
 */
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

/**
 * Normalizes a positive integer read from an attribute, such as a length or
 * count limit.
 * @param {*} value Raw value
 * @param {number|null} [fallback=null] Value used when the raw value is invalid
 * @returns {number|null} Positive integer, or the fallback
 */
const normalizePositiveInteger = (value, fallback = null) => {
  if (value === null || value === undefined || value === "") {
    return fallback;
  }

  const number = Number(value);
  return Number.isInteger(number) && number > 0 ? number : fallback;
};

/**
 * Turns a raw value into a safe element id fragment.
 * @param {*} value Raw value
 * @returns {string} Id fragment
 */
const sanitizeIdPart = (value) =>
  String(value || "")
    .replace(/[^A-Za-z0-9_-]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");

export {
  QUESTION_TYPES,
  buildQuestionsEditorIdPrefix,
  buildQuestionsEditorIds,
  cloneQuestion,
  createBlankQuestion,
  createBlankQuestionOption,
  getQuestionTypeLabel,
  normalizePositiveInteger,
  normalizeQuestionOptions,
  normalizeQuestions,
};
