import {
  normalizeUsers,
  sanitizeStringArray,
  toOptionalString,
  toTrimmedString,
} from "/static/js/common/utils.js";

/**
 * Adds the copy suffix to a given event name.
 * @param {*} name Event name
 * @returns {string} Name with copy suffix
 */
const appendCopySuffix = (name) => {
  const trimmed = toTrimmedString(name);
  if (!trimmed) {
    return "";
  }
  return `${trimmed} (copy)`;
};

/**
 * Sets category select based on id or matching display text.
 * @param {object} details Event payload
 */
const setCategoryValue = (details) => {
  const select = document.getElementById("category_id");
  if (!select) {
    return;
  }
  const options = Array.from(select.options || []);
  const byId = toOptionalString(details?.category_id);
  let resolvedValue = "";
  if (byId && options.some((option) => option.value === byId)) {
    resolvedValue = byId;
  } else {
    const categoryName = toTrimmedString(details?.category_name).toLowerCase();
    if (categoryName) {
      const match = options.find((option) => option.textContent.trim().toLowerCase() === categoryName);
      if (match) {
        resolvedValue = match.value;
      }
    }
  }
  select.value = resolvedValue;
  select.dispatchEvent(new Event("change", { bubbles: true }));
};

/**
 * Sets gallery images with sanitized urls.
 * @param {*} images Collection of image urls
 */
const setGalleryImages = (images) => {
  const gallery = document.querySelector('gallery-field[field-name="photos_urls"]');
  if (!gallery) {
    return;
  }
  const sanitized = sanitizeStringArray(images);
  if (typeof gallery._setImages === "function") {
    gallery._setImages(sanitized);
  } else {
    gallery.images = sanitized;
    gallery.requestUpdate?.();
  }
};

/**
 * Sets tag inputs with sanitized values.
 * @param {*} tags Tag values
 */
const setTags = (tags) => {
  const component = document.querySelector('multiple-inputs[field-name="tags"]');
  if (!component) {
    return;
  }
  const sanitized = sanitizeStringArray(tags);
  const items =
    sanitized.length > 0 ? sanitized.map((value, index) => ({ id: index, value })) : [{ id: 0, value: "" }];
  component.items = items;
  component._nextId = Math.max(items.length, 1);
  component.requestUpdate?.();
};

/**
 * Sets registration required toggle and hidden input.
 * @param {boolean} isRequired Whether registration is required
 */
const setRegistrationRequired = (isRequired) => {
  const toggle = document.getElementById("toggle_registration_required");
  const hidden = document.getElementById("registration_required");
  if (toggle) {
    toggle.checked = !!isRequired;
  }
  if (hidden) {
    hidden.value = isRequired ? "true" : "false";
  }
};

/**
 * Sets selected hosts on the hosts selector component.
 * @param {*} hosts Hosts payload
 */
const setHosts = (hosts) => {
  const selector = document.querySelector('user-search-selector[field-name="hosts"]');
  if (!selector) {
    return;
  }
  selector.selectedUsers = normalizeUsers(hosts);
  selector.requestUpdate?.();
};

/**
 * Sets sponsors on the sponsors section component.
 * @param {*} sponsors Sponsors payload
 */
const setSponsors = (sponsors) => {
  const section = document.querySelector("sponsors-section");
  if (!section) {
    return;
  }
  const normalized = Array.isArray(sponsors)
    ? sponsors.map((sponsor) => ({
        ...sponsor,
        level: toOptionalString(sponsor?.level),
      }))
    : [];
  section.selectedSponsors = normalized;
  section.requestUpdate?.();
};

/**
 * Normalizes speaker data, flattening nested user objects.
 * @param {*} speakers Raw speakers payload
 * @returns {object[]} Normalized speaker entries
 */
const normalizeSpeakers = (speakers) => {
  if (!Array.isArray(speakers)) {
    return [];
  }
  return speakers
    .map((speaker) => {
      if (speaker && typeof speaker === "object" && speaker.user && typeof speaker.user === "object") {
        return { ...speaker.user, featured: !!speaker.featured };
      }
      return speaker && typeof speaker === "object" ? { ...speaker, featured: !!speaker.featured } : null;
    })
    .filter(Boolean);
};

/**
 * Builds session entry objects compatible with the sessions UI.
 * @param {*} sessionsData Sessions data grouped or flat
 * @returns {object[]} Normalized session entries
 */
const buildSessionEntries = (sessionsData) => {
  if (!sessionsData) {
    return [];
  }
  const buckets = Array.isArray(sessionsData) ? sessionsData : Object.values(sessionsData);
  const entries = [];
  buckets.forEach((bucket) => {
    if (!Array.isArray(bucket)) {
      return;
    }
    bucket.forEach((session) => {
      if (!session || typeof session !== "object") {
        return;
      }
      entries.push({
        name: toOptionalString(session.name),
        description: toOptionalString(session.description),
        kind: toOptionalString(session.kind),
        location: toOptionalString(session.location),
        meeting_join_url: "",
        meeting_recording_url: "",
        meeting_requested: false,
        meeting_in_sync: false,
        meeting_password: "",
        meeting_error: "",
        starts_at: "",
        ends_at: "",
        speakers: normalizeSpeakers(session.speakers),
      });
    });
  });
  return entries;
};

/**
 * Sets sessions on the sessions section component.
 * @param {*} sessionsData Raw sessions data
 */
const setSessions = (sessionsData) => {
  const section = document.querySelector("sessions-section");
  if (!section) {
    return;
  }
  const entries = buildSessionEntries(sessionsData);
  section.sessions = entries.length > 0 ? entries : [];
  if (typeof section._initializeSessionIds === "function") {
    section._initializeSessionIds();
  }
  section.requestUpdate?.();
};

/**
 * Updates markdown editor content, syncing textarea and CodeMirror.
 * @param {*} content Markdown text
 */
const updateMarkdownContent = (content) => {
  const editor = document.querySelector("markdown-editor#description");
  if (!editor) {
    return;
  }
  const nextValue = toOptionalString(content);
  const textarea = editor.querySelector("textarea");
  if (textarea) {
    textarea.value = nextValue;
    textarea.dispatchEvent(new Event("input", { bubbles: true }));
  }
  const codeMirrorWrapper = editor.querySelector(".CodeMirror");
  const cmInstance = codeMirrorWrapper?.CodeMirror;
  if (cmInstance && typeof cmInstance.setValue === "function") {
    cmInstance.setValue(nextValue);
    if (typeof cmInstance.save === "function") {
      cmInstance.save();
    }
  }
};

/**
 * Updates timezone selector or select with a safe fallback.
 * @param {*} timezone Timezone value
 */
const updateTimezone = (timezone) => {
  const normalized = toOptionalString(timezone);

  const selector = document.querySelector("timezone-selector[name='timezone']");
  if (selector) {
    selector.value = normalized;
    selector.dispatchEvent(new Event("change", { bubbles: true }));
  }
};

export {
  appendCopySuffix,
  buildSessionEntries,
  normalizeSpeakers,
  setCategoryValue,
  setGalleryImages,
  setHosts,
  setRegistrationRequired,
  setSessions,
  setSponsors,
  setTags,
  updateMarkdownContent,
  updateTimezone,
};
