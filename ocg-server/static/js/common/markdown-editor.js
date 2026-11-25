import { html, nothing } from "lit";
import { createRef, ref } from "lit/directives/ref.js";
import { LitWrapper } from "/static/js/common/lit-wrapper.js";

// Shared inline SVG attributes for local EasyMDE toolbar icons.
const TOOLBAR_ICON_ATTRS =
  'viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
  'stroke-width="2" stroke-linecap="round" stroke-linejoin="round" ' +
  'aria-hidden="true" focusable="false"';

// Local inline SVG icons replacing Font Awesome CDN glyphs for EasyMDE toolbar buttons.
const TOOLBAR_ICONS = {
  bold:
    `<svg ${TOOLBAR_ICON_ATTRS}>` +
    '<path d="M6 4h8a4 4 0 0 1 0 8H6z"/>' +
    '<path d="M6 12h9a4 4 0 0 1 0 8H6z"/>' +
    "</svg>",
  checkList:
    `<svg ${TOOLBAR_ICON_ATTRS}>` +
    '<rect x="3" y="4" width="6" height="6" rx="1"/>' +
    '<path d="m4.5 7 1 1 2-2"/>' +
    '<line x1="13" y1="7" x2="21" y2="7"/>' +
    '<rect x="3" y="14" width="6" height="6" rx="1"/>' +
    '<line x1="13" y1="17" x2="21" y2="17"/>' +
    "</svg>",
  heading:
    `<svg ${TOOLBAR_ICON_ATTRS}>` +
    '<path d="M6 4v16"/>' +
    '<path d="M18 4v16"/>' +
    '<path d="M6 12h12"/>' +
    "</svg>",
  horizontalRule: `<svg ${TOOLBAR_ICON_ATTRS}><line x1="4" y1="12" x2="20" y2="12"/></svg>`,
  italic:
    `<svg ${TOOLBAR_ICON_ATTRS}>` +
    '<line x1="19" y1="4" x2="10" y2="4"/>' +
    '<line x1="14" y1="20" x2="5" y2="20"/>' +
    '<line x1="15" y1="4" x2="9" y2="20"/>' +
    "</svg>",
  link:
    `<svg ${TOOLBAR_ICON_ATTRS}>` +
    '<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/>' +
    '<path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>' +
    "</svg>",
  orderedList:
    `<svg ${TOOLBAR_ICON_ATTRS}>` +
    '<line x1="10" y1="6" x2="21" y2="6"/>' +
    '<line x1="10" y1="12" x2="21" y2="12"/>' +
    '<line x1="10" y1="18" x2="21" y2="18"/>' +
    '<path d="M4 6h1v4"/>' +
    '<path d="M4 10h2"/>' +
    '<path d="M6 18H4c0-1 2-2 2-3s-1-1.5-2-1"/>' +
    "</svg>",
  preview:
    `<svg ${TOOLBAR_ICON_ATTRS}>` +
    '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z"/>' +
    '<circle cx="12" cy="12" r="3"/>' +
    "</svg>",
  quote:
    `<svg ${TOOLBAR_ICON_ATTRS}>` +
    '<path d="M10 8H6a2 2 0 0 0-2 2v3a2 2 0 0 0 2 2h2v1a2 2 0 0 1-2 2"/>' +
    '<path d="M20 8h-4a2 2 0 0 0-2 2v3a2 2 0 0 0 2 2h2v1a2 2 0 0 1-2 2"/>' +
    "</svg>",
  redo:
    `<svg ${TOOLBAR_ICON_ATTRS}>` +
    '<path d="M21 7v6h-6"/>' +
    '<path d="M3 17a9 9 0 0 1 9-9 9 9 0 0 1 6 2.3L21 13"/>' +
    "</svg>",
  table:
    `<svg ${TOOLBAR_ICON_ATTRS}>` +
    '<rect x="3" y="4" width="18" height="16" rx="2"/>' +
    '<line x1="3" y1="10" x2="21" y2="10"/>' +
    '<line x1="3" y1="15" x2="21" y2="15"/>' +
    '<line x1="9" y1="4" x2="9" y2="20"/>' +
    '<line x1="15" y1="4" x2="15" y2="20"/>' +
    "</svg>",
  undo:
    `<svg ${TOOLBAR_ICON_ATTRS}>` +
    '<path d="M3 7v6h6"/>' +
    '<path d="M21 17a9 9 0 0 0-9-9 9 9 0 0 0-6 2.3L3 13"/>' +
    "</svg>",
  unorderedList:
    `<svg ${TOOLBAR_ICON_ATTRS}>` +
    '<line x1="9" y1="6" x2="20" y2="6"/>' +
    '<line x1="9" y1="12" x2="20" y2="12"/>' +
    '<line x1="9" y1="18" x2="20" y2="18"/>' +
    '<circle cx="4" cy="6" r="1" fill="currentColor"/>' +
    '<circle cx="4" cy="12" r="1" fill="currentColor"/>' +
    '<circle cx="4" cy="18" r="1" fill="currentColor"/>' +
    "</svg>",
};

/**
 * Markdown editor component using EasyMDE.
 * Provides rich text editing with markdown support.
 * @extends LitWrapper
 */
export class MarkdownEditor extends LitWrapper {
  /**
   * Component properties definition
   * @property {string} id - Editor ID attribute
   * @property {string} inputId - Textarea ID attribute
   * @property {string} name - Form input name
   * @property {string} content - Initial markdown content
   * @property {boolean} required - Whether input is required
   * @property {Function} onChange - Callback for content changes
   * @property {boolean} mini - Use compact editor layout
   * @property {number} maxlength - Maximum character length
   */
  static properties = {
    id: { type: String },
    inputId: { type: String, attribute: "input-id" },
    name: { type: String },
    content: { type: String },
    required: { type: Boolean },
    onChange: { type: Function },
    mini: { type: Boolean },
    disabled: { type: Boolean },
    maxlength: { type: Number },
  };

  /** @type {import('lit').Ref<HTMLTextAreaElement>} Reference to textarea */
  textareaRef = createRef();

  constructor() {
    super();
    this.id = "id";
    this.inputId = "";
    this.name = undefined;
    this.content = "";
    this.required = false;
    this.onChange = undefined;
    this.mini = false;
    this.disabled = false;
    this.maxlength = undefined;
  }

  firstUpdated() {
    super.firstUpdated();

    const textarea = this.textareaRef.value;
    if (!textarea) {
      return;
    }

    this._initEditor(textarea);
  }

  /**
   * Initializes the EasyMDE editor instance.
   * @param {HTMLTextAreaElement} textarea - The textarea element to enhance
   * @private
   */
  _initEditor(textarea) {
    // Disable CDN-backed Font Awesome and dictionary spellcheck fetches to stay CSP-clean.
    // CodeMirror's dictionary spellcheck is omitted; desktop uses plain textarea editing
    // and touch devices use browser spellcheck where supported.
    const markdownEditor = new EasyMDE({
      autoDownloadFontAwesome: false,
      // Fix for hidden textarea
      autoRefresh: { delay: 300 },
      element: textarea,
      forceSync: true,
      initialValue: this.content,
      previewClass: "markdown",
      // Match server-side rendering, where single line breaks are soft breaks
      renderingConfig: { singleLineBreaks: false },
      spellChecker: false,
      status: false,
      toolbar: buildEasyMdeToolbar(EasyMDE),
    });

    markdownEditor.codemirror.on("change", () => {
      if (this.onChange) {
        this.onChange(markdownEditor.value());
      }
    });

    // Show textarea to avoid console errors with required attribute
    textarea.style.display = "block";
    // Set after init: CodeMirror copies a textarea tabindex onto its own input.
    textarea.tabIndex = -1;
  }

  render() {
    // The textarea only carries the form value and validation; EasyMDE renders the editable input.
    return html`
      <div class="relative text-sm/6 ${this.mini ? "mini" : ""}">
        <textarea
          ${ref(this.textareaRef)}
          id=${this.inputId || nothing}
          name=${this.name || this.id}
          class="absolute top-0 left-0 opacity-0 p-0"
          aria-hidden="true"
          ?required=${this.required}
          ?disabled=${this.disabled}
          maxlength=${this.maxlength}
        ></textarea>
      </div>
    `;
  }
}

/**
 * Builds the EasyMDE toolbar definition using local inline SVG icons.
 * @param {typeof EasyMDE} editorCtor EasyMDE constructor exposing built-in action helpers.
 * @returns {Array<string|object>} Toolbar definition passed to EasyMDE.
 */
const buildEasyMdeToolbar = (editorCtor) => [
  {
    action: editorCtor.toggleBold,
    icon: TOOLBAR_ICONS.bold,
    name: "bold",
    title: "Bold",
  },
  {
    action: editorCtor.toggleItalic,
    icon: TOOLBAR_ICONS.italic,
    name: "italic",
    title: "Italic",
  },
  {
    action: editorCtor.toggleHeadingSmaller,
    icon: TOOLBAR_ICONS.heading,
    name: "heading",
    title: "Heading",
  },
  "|",
  {
    action: editorCtor.toggleBlockquote,
    icon: TOOLBAR_ICONS.quote,
    name: "quote",
    title: "Quote",
  },
  {
    action: editorCtor.toggleUnorderedList,
    icon: TOOLBAR_ICONS.unorderedList,
    name: "unordered-list",
    title: "Generic List",
  },
  {
    action: editorCtor.toggleOrderedList,
    icon: TOOLBAR_ICONS.orderedList,
    name: "ordered-list",
    title: "Numbered List",
  },
  {
    action: editorCtor.toggleCheckList,
    icon: TOOLBAR_ICONS.checkList,
    name: "check-list",
    title: "Check List",
  },
  "|",
  {
    action: editorCtor.drawLink,
    icon: TOOLBAR_ICONS.link,
    name: "link",
    title: "Create Link",
  },
  {
    action: editorCtor.drawTable,
    icon: TOOLBAR_ICONS.table,
    name: "table",
    title: "Insert Table",
  },
  {
    action: editorCtor.drawHorizontalRule,
    icon: TOOLBAR_ICONS.horizontalRule,
    name: "horizontal-rule",
    title: "Insert Horizontal Line",
  },
  "|",
  {
    action: editorCtor.togglePreview,
    icon: TOOLBAR_ICONS.preview,
    name: "preview",
    noDisable: true,
    title: "Toggle Preview",
  },
  "|",
  {
    action: editorCtor.undo,
    icon: TOOLBAR_ICONS.undo,
    name: "undo",
    noDisable: true,
    title: "Undo",
  },
  {
    action: editorCtor.redo,
    icon: TOOLBAR_ICONS.redo,
    name: "redo",
    noDisable: true,
    title: "Redo",
  },
];

customElements.define("markdown-editor", MarkdownEditor);
