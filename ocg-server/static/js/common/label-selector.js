import { normalizeLabels } from "/static/js/common/labels.js";
import { MultiSelect } from "/static/js/common/multi-select.js";

const DEFAULT_PLACEHOLDER = "Search labels";

/**
 * LabelSelector renders a searchable multi-select for event labels.
 *
 * It maps `labels` to the generic multi-select options and keeps the label
 * texts and default field name.
 *
 * @property {Array<Object>} labels Available labels for selection
 * @property {Array<string>} selected Selected event_label_id values
 * @fires change Bubbling native event dispatched after a selection change renders
 */
export class LabelSelector extends MultiSelect {
  static properties = {
    labels: { type: Array, attribute: "labels" },
  };

  constructor() {
    super();
    this.emptyMessage = "No labels found";
    this.labels = [];
    this.name = "label_ids";
    this.placeholder = DEFAULT_PLACEHOLDER;
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
        value: label.event_label_id,
      }));
    }
    super.willUpdate(changedProperties);
  }
}

if (!customElements.get("label-selector")) {
  customElements.define("label-selector", LabelSelector);
}
