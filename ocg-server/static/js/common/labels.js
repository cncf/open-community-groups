/**
 * Builds the inline style used by colored label chips.
 * @param {string} color Label color
 * @returns {string} Inline style declaration
 */
export const labelColorStyle = (color) =>
  `--label-color:${color};border-color:var(--label-color);background-color:color-mix(in srgb, var(--label-color) 30%, transparent);`;

/**
 * Normalizes event labels into unique named entries with string ids.
 * @param {unknown} labels Raw labels
 * @returns {Array<{color: string, event_label_id: string, name: string}>}
 */
export const normalizeLabels = (labels) => {
  if (!Array.isArray(labels)) {
    return [];
  }

  const normalized = [];
  const seen = new Set();
  for (const label of labels) {
    const eventLabelId = String(label?.event_label_id || "").trim();
    const name = String(label?.name || "").trim();
    const color = String(label?.color || "").trim();
    if (!eventLabelId || !name || seen.has(eventLabelId)) {
      continue;
    }

    seen.add(eventLabelId);
    normalized.push({ color, event_label_id: eventLabelId, name });
  }
  return normalized;
};
