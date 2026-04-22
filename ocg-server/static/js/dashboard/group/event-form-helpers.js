import {
  normalizeUsers,
  sanitizeStringArray,
  toOptionalString,
  toTrimmedString,
} from "/static/js/common/utils.js";
import { confirmAction } from "/static/js/common/alerts.js";

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
 * Sets event reminder toggle and hidden input.
 * @param {boolean} isEnabled Whether event reminders are enabled
 */
const setEventReminderEnabled = (isEnabled) => {
  const toggle = document.getElementById("toggle_event_reminder_enabled");
  const hidden = document.getElementById("event_reminder_enabled");
  if (toggle) {
    toggle.checked = !!isEnabled;
  }
  if (hidden) {
    hidden.value = isEnabled ? "true" : "false";
  }
};

/**
 * Sets event payment currency and triggers dependent ticketing UI updates.
 * @param {*} paymentCurrencyCode Event payment currency code
 */
const setPaymentCurrencyCode = (paymentCurrencyCode) => {
  const select = document.getElementById("payment_currency_code");
  if (!select) {
    return;
  }

  select.value = toOptionalString(paymentCurrencyCode);
  select.dispatchEvent(new Event("input", { bubbles: true }));
  select.dispatchEvent(new Event("change", { bubbles: true }));
};

/**
 * Removes copied ticket price window dates from ticketing payload.
 * @param {*} ticketTypes Ticket types payload
 * @returns {Array<object>} Ticket types without copied price window dates
 */
const clearCopiedTicketTypeDates = (ticketTypes) => {
  if (!Array.isArray(ticketTypes)) {
    return [];
  }

  return ticketTypes.map((ticketType) => ({
    ...ticketType,
    event_ticket_type_id: "",
    price_windows: Array.isArray(ticketType?.price_windows)
      ? ticketType.price_windows.map((priceWindow) => ({
          ...priceWindow,
          event_ticket_price_window_id: "",
          starts_at: "",
          ends_at: "",
        }))
      : [],
  }));
};

/**
 * Removes copied discount availability dates from discount payload.
 * @param {*} discountCodes Discount codes payload
 * @returns {Array<object>} Discount codes without copied dates
 */
const clearCopiedDiscountCodeDates = (discountCodes) => {
  if (!Array.isArray(discountCodes)) {
    return [];
  }

  return discountCodes.map((discountCode) => ({
    ...discountCode,
    available_dirty:
      String(discountCode?.available_override_active) === "true" &&
      Number.isFinite(Number.parseInt(discountCode?.available, 10)),
    event_discount_code_id: "",
    starts_at: "",
    ends_at: "",
  }));
};

/**
 * Replaces ticket types in the ticketing editor.
 * @param {*} ticketTypes Ticket types payload
 */
const setTicketTypes = (ticketTypes) => {
  const root = document.getElementById("ticket-types-ui");
  if (!root) {
    return;
  }

  root.setTicketTypes?.(clearCopiedTicketTypeDates(ticketTypes));
};

/**
 * Replaces discount codes in the ticketing editor.
 * @param {*} discountCodes Discount codes payload
 */
const setDiscountCodes = (discountCodes) => {
  const root = document.getElementById("discount-codes-ui");
  if (!root) {
    return;
  }

  root.setDiscountCodes?.(clearCopiedDiscountCodeDates(discountCodes));
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
        cfs_submission_id: toOptionalString(session.cfs_submission_id),
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

/**
 * Wires a confirmation warning when clearing event dates would remove sessions.
 * @param {Object} options - Helper options
 * @param {HTMLElement|null} options.saveButton - Button that triggers the save
 * @param {string} [options.startsAtInputId] - Event start input id
 * @param {string} [options.endsAtInputId] - Event end input id
 * @param {string} [options.sessionsFormSelector] - Sessions form selector
 */
const initializeSessionsRemovalWarning = ({
  saveButton,
  startsAtInputId = "starts_at",
  endsAtInputId = "ends_at",
  sessionsFormSelector = "#sessions-form",
} = {}) => {
  if (!saveButton) {
    return;
  }

  let skipSessionsRemovalWarning = false;

  const hasConfiguredSessions = () => {
    const sessionsSection = document.querySelector("sessions-section");
    if (Array.isArray(sessionsSection?.sessions)) {
      return sessionsSection.sessions.length > 0;
    }

    return document.querySelectorAll(`${sessionsFormSelector} input[name^="sessions["]`).length > 0;
  };

  const shouldWarnAboutRemovingSessions = () => {
    const startsAtValue = document.getElementById(startsAtInputId)?.value.trim() || "";
    const endsAtValue = document.getElementById(endsAtInputId)?.value.trim() || "";

    return !startsAtValue && !endsAtValue && hasConfiguredSessions();
  };

  saveButton.addEventListener(
    "click",
    (event) => {
      if (skipSessionsRemovalWarning) {
        skipSessionsRemovalWarning = false;
        return;
      }

      if (!shouldWarnAboutRemovingSessions()) {
        return;
      }

      event.preventDefault();
      event.stopImmediatePropagation();

      void confirmAction({
        message:
          "Saving this event without start and end dates will remove all sessions. Do you want to continue?",
        confirmText: "Continue",
      }).then((confirmed) => {
        if (!confirmed) {
          return;
        }

        skipSessionsRemovalWarning = true;
        saveButton.click();
      });
    },
    true,
  );
};

export {
  appendCopySuffix,
  buildSessionEntries,
  initializeSessionsRemovalWarning,
  normalizeSpeakers,
  setCategoryValue,
  setDiscountCodes,
  setEventReminderEnabled,
  setGalleryImages,
  setHosts,
  setPaymentCurrencyCode,
  setRegistrationRequired,
  setSessions,
  setSponsors,
  setTags,
  setTicketTypes,
  updateMarkdownContent,
  updateTimezone,
};
