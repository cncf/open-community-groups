import { MultiSelect } from "/static/js/common/multi-select.js";

const DEFAULT_PLACEHOLDER = "Search labels";

/**
 * CfsLabelSelector renders a searchable multi-select for CFS labels.
 *
 * It maps `labels` to the generic multi-select options and keeps the CFS
 * texts, default field name and `data-cfs-label-*` markers.
 *
 * @property {Array<Object>} labels Available labels for selection
 * @property {Array<string>} selected Selected event_cfs_label_id values
 * @fires change Bubbling native event dispatched after a selection change renders
 */
export class CfsLabelSelector extends MultiSelect {
  static properties = {
    labels: { type: Array, attribute: "labels" },
  };

  constructor() {
    super();
    this.emptyMessage = "No labels found";
    this.labels = [];
    this.name = "label_ids";
    this.placeholder = DEFAULT_PLACEHOLDER;
    this._addMorePlaceholder = "Add labels";
    this._clearSelectionLabel = "Clear selected labels";
  }

  /**
   * Normalizes labels and maps them to options before rendering.
   * @param {Map<string, unknown>} changedProperties Changed reactive properties
   */
  willUpdate(changedProperties) {
    if (changedProperties.has("labels")) {
      this.labels = normalizeLabels(this.labels);
      this.options = this.labels.map((label) => ({
        color: label.color,
        name: label.name,
        value: label.event_cfs_label_id,
      }));
    }
    super.willUpdate(changedProperties);
  }

  updated(changedProperties) {
    super.updated(changedProperties);

    // Keep the legacy markers next to the generic ones.
    this._searchAnchorElement()?.toggleAttribute("data-cfs-label-search", true);
    this._dropdownElement()?.toggleAttribute("data-cfs-label-dropdown", true);
  }
}

/**
 * Normalizes labels into unique entries with string ids.
 * @param {unknown} labels Raw labels
 * @returns {Array<{color: string, event_cfs_label_id: string, name: string}>}
 */
const normalizeLabels = (labels) => {
  if (!Array.isArray(labels)) {
    return [];
  }

  const normalized = [];
  const seen = new Set();
  for (const label of labels) {
    const eventCfsLabelId = String(label?.event_cfs_label_id || "");
    const name = String(label?.name || "").trim();
    const color = String(label?.color || "").trim();
    if (!eventCfsLabelId || !name || seen.has(eventCfsLabelId)) {
      continue;
    }

    seen.add(eventCfsLabelId);
    normalized.push({ color, event_cfs_label_id: eventCfsLabelId, name });
  }
  return normalized;
};

if (!customElements.get("cfs-label-selector")) {
  customElements.define("cfs-label-selector", CfsLabelSelector);
}
