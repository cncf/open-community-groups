import { showErrorAlert } from "/static/js/common/alerts.js";
import "/static/js/common/breadcrumb-nav.js";
import { convertDateTimeLocalToISO, lockBodyScroll, unlockBodyScroll } from "/static/js/common/common.js";
import { ocgFetch } from "/static/js/common/fetch.js";
import "/static/js/common/images-gallery.js";
import "/static/js/common/user-chip.js";
import { EVENT_PAGE_FORM_IDS } from "/static/js/dashboard/group/event-page-shared.js";

const PREVIEW_ENDPOINT = "/dashboard/group/events/preview";
const PREVIEW_BUTTON_ID = "event-preview-button";
const PREVIEW_MODAL_ROOT_ID = "event-preview-modal-root";
const modalState = new WeakMap();

/**
 * Initializes event preview behavior for an add or update event page.
 * @param {Object} config Initialization config.
 * @param {Document|Element} config.pageRoot Event page root.
 * @returns {void}
 */
export const initializeEventPreview = ({ pageRoot }) => {
  const previewButton = pageRoot?.querySelector?.(`#${PREVIEW_BUTTON_ID}`);
  const modalRoot =
    pageRoot?.ownerDocument?.getElementById?.(PREVIEW_MODAL_ROOT_ID) ||
    document.getElementById(PREVIEW_MODAL_ROOT_ID);
  if (!previewButton || !modalRoot || previewButton.dataset.eventPreviewReady === "true") {
    return;
  }

  previewButton.dataset.eventPreviewReady = "true";
  previewButton.addEventListener("click", async () => {
    if (previewButton.disabled) {
      return;
    }

    previewButton.disabled = true;
    previewButton.setAttribute("aria-busy", "true");

    try {
      const response = await ocgFetch(PREVIEW_ENDPOINT, {
        body: buildEventPreviewPayload(pageRoot),
        credentials: "same-origin",
        headers: {
          Accept: "text/html",
          "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
        },
        method: "POST",
      });

      if (!response.ok) {
        throw new Error(`Preview request failed with status ${response.status}`);
      }

      openEventPreviewModal(modalRoot, await response.text());
    } catch (_) {
      showErrorAlert("Unable to open the event preview. Please try again.");
    } finally {
      previewButton.disabled = false;
      previewButton.removeAttribute("aria-busy");
    }
  });
};

/**
 * Builds the URL-encoded preview request payload from the current editor state.
 * @param {Document|Element} pageRoot Event page root.
 * @returns {URLSearchParams} Request payload.
 */
export const buildEventPreviewPayload = (pageRoot) => {
  const payload = new URLSearchParams();

  for (const formId of EVENT_PAGE_FORM_IDS) {
    const form = pageRoot.querySelector?.(`#${formId}`);
    if (!form) {
      continue;
    }

    for (const [name, value] of new FormData(form).entries()) {
      appendPreviewFormValue(payload, name, value);
    }
  }

  normalizePreviewTimezone(payload);
  payload.set("preview_context", JSON.stringify(collectEventPreviewContext(pageRoot)));
  return payload;
};

/**
 * Collects display-only preview context from dashboard controls and selectors.
 * @param {Document|Element} pageRoot Event page root.
 * @returns {Object} Preview context.
 */
export const collectEventPreviewContext = (pageRoot) => {
  const dashboardContent =
    pageRoot.closest?.("#dashboard-content") || document.getElementById("dashboard-content");
  const kindSelect = pageRoot.querySelector?.("#kind_id");
  const categorySelect = pageRoot.querySelector?.("#category_id");
  const sessionsSection = pageRoot.querySelector?.("sessions-section");

  return compactObject({
    category_label: selectedOptionLabel(categorySelect),
    community: compactObject({
      banner_url: firstValue(
        pageRoot.dataset?.communityBannerUrl,
        dashboardContent?.dataset?.communityBannerUrl,
      ),
      display_name: firstValue(
        pageRoot.dataset?.communityDisplayName,
        dashboardContent?.dataset?.communityDisplayName,
        dashboardContent?.dataset?.community,
      ),
      logo_url: firstValue(pageRoot.dataset?.communityLogoUrl, dashboardContent?.dataset?.communityLogoUrl),
      name: firstValue(pageRoot.dataset?.communityName, dashboardContent?.dataset?.community),
    }),
    group: compactObject({
      banner_url: firstValue(pageRoot.dataset?.groupBannerUrl, dashboardContent?.dataset?.groupBannerUrl),
      logo_url: firstValue(pageRoot.dataset?.groupLogoUrl, dashboardContent?.dataset?.groupLogoUrl),
      name: firstValue(pageRoot.dataset?.groupName, dashboardContent?.dataset?.groupName),
      slug: firstValue(pageRoot.dataset?.groupSlug, dashboardContent?.dataset?.groupSlug),
    }),
    hosts: collectPeople(pageRoot.querySelector?.('user-search-selector[field-name="hosts"]')?.selectedUsers),
    kind_label: selectedOptionLabel(kindSelect),
    public_url:
      pageRoot.dataset?.eventPublicUrlEnabled === "true"
        ? firstValue(pageRoot.dataset?.eventPublicUrl)
        : undefined,
    sessions: collectSessionContexts(sessionsSection),
    speakers: collectPeople(
      pageRoot.querySelector?.('speakers-selector[field-name-prefix="speakers"]')?.selectedSpeakers,
    ),
    sponsors: collectSponsors(pageRoot.querySelector?.("sponsors-section")?.selectedSponsors),
  });
};

/**
 * Inserts preview HTML and binds modal close behavior.
 * @param {HTMLElement} modalRoot Modal root element.
 * @param {string} html Modal HTML.
 * @returns {void}
 */
export const openEventPreviewModal = (modalRoot, html) => {
  closeEventPreviewModal(modalRoot);
  modalRoot.innerHTML = html;
  lockBodyScroll();

  const handleClick = (event) => {
    if (event.target.closest("[data-event-preview-close]")) {
      closeEventPreviewModal(modalRoot);
    }
  };
  const handleKeydown = (event) => {
    if (event.key === "Escape") {
      closeEventPreviewModal(modalRoot);
    }
  };

  modalRoot.addEventListener("click", handleClick);
  document.addEventListener("keydown", handleKeydown);
  modalState.set(modalRoot, { handleClick, handleKeydown });
};

/**
 * Closes the active preview modal, if present.
 * @param {HTMLElement} modalRoot Modal root element.
 * @returns {void}
 */
export const closeEventPreviewModal = (modalRoot) => {
  const state = modalState.get(modalRoot);
  if (!state) {
    modalRoot.innerHTML = "";
    return;
  }

  modalRoot.removeEventListener("click", state.handleClick);
  document.removeEventListener("keydown", state.handleKeydown);
  modalState.delete(modalRoot);
  modalRoot.innerHTML = "";
  unlockBodyScroll();
};

/**
 * Appends a single form value to the preview payload.
 * @param {URLSearchParams} payload Payload being built.
 * @param {string} name Field name.
 * @param {FormDataEntryValue} value Field value.
 * @returns {void}
 */
const appendPreviewFormValue = (payload, name, value) => {
  if (!name || name.startsWith("toggle_") || value instanceof File) {
    return;
  }

  const stringValue = String(value).trim();
  if (stringValue === "") {
    return;
  }

  payload.append(name, normalizePreviewParameterValue(name, stringValue));
};

/**
 * Normalizes datetime-local values to the shape expected by the Rust preview parser.
 * @param {string} name Field name.
 * @param {string} value Field value.
 * @returns {string} Normalized value.
 */
const normalizePreviewParameterValue = (name, value) => {
  const isEventDate = /^(starts_at|ends_at|cfs_starts_at|cfs_ends_at)$/.test(name);
  const isSessionDate = /^sessions\[\d+\]\[(starts_at|ends_at)\]$/.test(name);
  return isEventDate || isSessionDate ? convertDateTimeLocalToISO(value) : value;
};

/**
 * Replaces the submitted timezone with a short display label for the preview.
 * @param {URLSearchParams} payload Payload being built.
 * @returns {void}
 */
const normalizePreviewTimezone = (payload) => {
  const timezone = payload.get("timezone");
  if (!timezone) {
    return;
  }

  const timezoneLabel = getShortTimezoneLabel(timezone, payload.get("starts_at"));
  if (timezoneLabel) {
    payload.set("timezone", timezoneLabel);
  }
};

/**
 * Returns the short timezone label used by the public event page.
 * @param {string} timezone IANA timezone identifier.
 * @param {string|null} startsAt Event start date.
 * @returns {string|undefined}
 */
const getShortTimezoneLabel = (timezone, startsAt) => {
  const date = getTimezoneLabelDate(startsAt);
  try {
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone: timezone,
      timeZoneName: "short",
    }).formatToParts(date);
    return parts.find((part) => part.type === "timeZoneName")?.value;
  } catch (_) {
    return undefined;
  }
};

/**
 * Builds a stable date for resolving the timezone abbreviation.
 * @param {string|null} startsAt Event start date.
 * @returns {Date}
 */
const getTimezoneLabelDate = (startsAt) => {
  const datePart = String(startsAt || "").match(/^\d{4}-\d{2}-\d{2}/)?.[0];
  return datePart ? new Date(`${datePart}T12:00:00Z`) : new Date();
};

/**
 * Reads the selected option label when a select has a real value.
 * @param {HTMLSelectElement|null|undefined} select Select element.
 * @returns {string|undefined} Selected option label.
 */
const selectedOptionLabel = (select) => {
  if (!select?.value) {
    return undefined;
  }

  return toOptionalString(select.selectedOptions?.[0]?.textContent);
};

/**
 * Collects session context from the sessions custom element.
 * @param {Element|null|undefined} sessionsSection Sessions element.
 * @returns {Array<Object>} Session display context.
 */
const collectSessionContexts = (sessionsSection) => {
  const sessions = readArray(sessionsSection?.sessions);
  const sessionKinds = readArray(sessionsSection?.sessionKinds);
  const kindLabels = new Map(
    sessionKinds.map((kind) => [String(kind?.session_kind_id || ""), toOptionalString(kind?.display_name)]),
  );

  return sessions.map((session) =>
    compactObject({
      kind_label: firstValue(kindLabels.get(String(session?.kind || "")), session?.kind),
      name: session?.name,
      speakers: collectPeople(session?.speakers),
    }),
  );
};

/**
 * Collects people selector data into preview context.
 * @param {unknown} people Raw people data.
 * @returns {Array<Object>} Normalized people.
 */
const collectPeople = (people) =>
  readArray(people)
    .map((person) =>
      compactObject({
        company: person?.company,
        featured: typeof person?.featured === "boolean" ? person.featured : undefined,
        name: person?.name,
        photo_url: person?.photo_url,
        title: person?.title,
        username: person?.username,
      }),
    )
    .filter((person) => Object.keys(person).length > 0);

/**
 * Collects sponsor selector data into preview context.
 * @param {unknown} sponsors Raw sponsors data.
 * @returns {Array<Object>} Normalized sponsors.
 */
const collectSponsors = (sponsors) =>
  readArray(sponsors)
    .map((sponsor) =>
      compactObject({
        level: sponsor?.level,
        logo_url: sponsor?.logo_url,
        name: sponsor?.name,
        website_url: sponsor?.website_url,
      }),
    )
    .filter((sponsor) => Object.keys(sponsor).length > 0);

/**
 * Returns the first non-empty string from the provided values.
 * @param {...unknown} values Candidate values.
 * @returns {string|undefined} First non-empty string.
 */
const firstValue = (...values) => values.map(toOptionalString).find(Boolean);

/**
 * Converts a value to a trimmed string, dropping empty values.
 * @param {unknown} value Raw value.
 * @returns {string|undefined} Normalized string.
 */
const toOptionalString = (value) => {
  const normalized = String(value ?? "").trim();
  return normalized || undefined;
};

/**
 * Reads an array-like value safely.
 * @param {unknown} value Raw value.
 * @returns {Array} Array value.
 */
const readArray = (value) => {
  if (Array.isArray(value)) {
    return value;
  }

  if (typeof value === "string") {
    try {
      const parsed = JSON.parse(value);
      return Array.isArray(parsed) ? parsed : [];
    } catch (_) {
      return [];
    }
  }

  return [];
};

/**
 * Removes empty object properties recursively.
 * @param {Object} object Raw object.
 * @returns {Object} Compacted object.
 */
const compactObject = (object) =>
  Object.fromEntries(
    Object.entries(object)
      .map(([key, value]) => [key, compactValue(value)])
      .filter(([, value]) => value !== undefined),
  );

/**
 * Compacts supported JSON values.
 * @param {unknown} value Raw value.
 * @returns {unknown} Compacted value.
 */
const compactValue = (value) => {
  if (value === null || value === undefined) {
    return undefined;
  }
  if (typeof value === "boolean" || typeof value === "number") {
    return value;
  }
  if (Array.isArray(value)) {
    return value.length > 0 ? value : undefined;
  }
  if (value && typeof value === "object") {
    const compacted = compactObject(value);
    return Object.keys(compacted).length > 0 ? compacted : undefined;
  }
  return toOptionalString(value);
};
