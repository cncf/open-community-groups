import { showErrorAlert } from "/static/js/common/alerts.js";
import "/static/js/common/breadcrumb-nav.js";
import { convertDateTimeLocalToISO } from "/static/js/common/datetime.js";
import { closestElement, getElementById, markDatasetReady, setElementHidden } from "/static/js/common/dom.js";
import { ocgFetch } from "/static/js/common/fetch.js";
import { loadMap } from "/static/js/common/location/leaflet.js";
import {
  bindModalDismissListeners,
  closeModalBodyScroll,
  openModalBodyScroll,
} from "/static/js/common/modals/modal-lifecycle.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import { setTrustedHtml } from "/static/js/common/trusted-html.js";
import { parseJsonAttribute } from "/static/js/common/utils.js";
import "/static/js/common/modals/images-gallery.js";
import "/static/js/common/users/user-chip.js";
import { EVENT_PAGE_FORM_IDS } from "/static/js/dashboard/group/event-page-shared.js";

const PREVIEW_ENDPOINT = "/dashboard/group/events/preview";
const PREVIEW_BUTTON_ID = "event-preview-button";
const PREVIEW_MODAL_ROOT_ID = "event-preview-modal-root";
const LOGIN_PATH = "/log-in";
const PREVIEW_MODAL_MARKER = "data-event-preview-modal";
const EVENT_PREVIEW_FORM_IDS = EVENT_PAGE_FORM_IDS.filter((formId) => formId !== "payments-form");
const EVENT_PREVIEW_CLIENT_RENDERED_FIELDS = new Set(["luma_url", "meetup_url"]);
const EVENT_PREVIEW_SOCIAL_LINKS = [
  {
    fieldName: "meetup_url",
    iconName: "meetup",
    platformName: "Meetup",
  },
  {
    fieldName: "luma_url",
    iconName: "luma",
    platformName: "Luma",
  },
];
const modalState = new WeakMap();
const MODAL_WAS_CLOSED = false;
const MODAL_WAS_OPEN = true;

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
    getElementById(document, PREVIEW_MODAL_ROOT_ID);
  if (!modalRoot || !markDatasetReady(previewButton, "eventPreviewReady")) {
    return;
  }

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

      const previewHtml = await response.text();
      if (isLoginResponse(response) || !previewHtml.includes(PREVIEW_MODAL_MARKER)) {
        throw new Error("Preview response did not contain an event preview.");
      }

      openEventPreviewModal(modalRoot, previewHtml, pageRoot);
    } catch (_) {
      showErrorAlert("Unable to open the event preview. Please try again.");
    } finally {
      previewButton.disabled = false;
      previewButton.removeAttribute("aria-busy");
    }
  });
};

/**
 * Checks whether the preview request resolved to the login page.
 * @param {Response} response Preview endpoint response
 * @returns {boolean}
 */
const isLoginResponse = (response) => {
  const responseUrl = new URL(response.url, window.location.origin);
  return responseUrl.pathname === LOGIN_PATH;
};

/**
 * Builds the URL-encoded preview request payload from the current editor state.
 * @param {Document|Element} pageRoot Event page root.
 * @returns {URLSearchParams} Request payload.
 */
export const buildEventPreviewPayload = (pageRoot) => {
  const payload = new URLSearchParams();

  for (const formId of EVENT_PREVIEW_FORM_IDS) {
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
const collectEventPreviewContext = (pageRoot) => {
  const dashboardContent = getDashboardContent(pageRoot);
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
    sessions: collectSessionContexts(sessionsSection),
    speakers: collectPeople(
      pageRoot.querySelector?.('speakers-selector[field-name-prefix="speakers"]')?.selectedSpeakers,
    ),
    sponsors: collectSponsors(pageRoot.querySelector?.("sponsors-section")?.selectedSponsors),
  });
};

/**
 * Finds the dashboard content root for event preview context.
 * @param {Document|Element} pageRoot Event page root.
 * @returns {HTMLElement|null} Dashboard content root.
 */
const getDashboardContent = (pageRoot) =>
  pageRoot.closest?.("#dashboard-content") || getElementById(document, "dashboard-content");

/**
 * Inserts preview HTML and binds modal close behavior.
 * @param {HTMLElement} modalRoot Modal root element.
 * @param {string} html Modal HTML.
 * @param {Document|Element} [pageRoot=document] Event page root.
 * @returns {void}
 */
export const openEventPreviewModal = (modalRoot, html, pageRoot = document) => {
  closeEventPreviewModal(modalRoot);
  setTrustedHtml(modalRoot, html);
  initializeEventPreviewMaps(modalRoot, pageRoot);
  initializeEventPreviewDraftSections(modalRoot, pageRoot);
  openModalBodyScroll(MODAL_WAS_CLOSED);

  const handleClick = (event) => {
    if (closestElement(event.target, "[data-event-preview-close]")) {
      closeEventPreviewModal(modalRoot);
    }
  };
  const handleKeydown = (event) => {
    if (isEscapeEvent(event)) {
      closeEventPreviewModal(modalRoot);
    }
  };

  modalRoot.addEventListener("click", handleClick);
  const removeDismissListeners = bindModalDismissListeners({ onKeydown: handleKeydown });
  modalState.set(modalRoot, { handleClick, removeDismissListeners });
};

/**
 * Closes the active preview modal, if present.
 * @param {HTMLElement} modalRoot Modal root element.
 * @returns {void}
 */
const closeEventPreviewModal = (modalRoot) => {
  const state = modalState.get(modalRoot);
  if (!state) {
    modalRoot.replaceChildren();
    return;
  }

  modalRoot.removeEventListener("click", state.handleClick);
  state.removeDismissListeners();
  modalState.delete(modalRoot);
  modalRoot.replaceChildren();
  closeModalBodyScroll(MODAL_WAS_OPEN);
};

/**
 * Initializes preview maps from the editor coordinates, when available.
 * @param {HTMLElement} modalRoot Modal root element.
 * @param {Document|Element} pageRoot Event page root.
 * @returns {void}
 */
const initializeEventPreviewMaps = (modalRoot, pageRoot) => {
  const latitude = readPreviewCoordinate(pageRoot, "latitude", "initial-latitude");
  const longitude = readPreviewCoordinate(pageRoot, "longitude", "initial-longitude");
  if (latitude === null || longitude === null) {
    return;
  }

  modalRoot.querySelectorAll("[data-event-preview-location-map]").forEach((mapRoot) => {
    initializeEventPreviewMap(mapRoot, latitude, longitude);
  });
};

/**
 * Initializes one preview map container.
 * @param {Element} mapRoot Preview map root.
 * @param {number} latitude Map latitude.
 * @param {number} longitude Map longitude.
 * @returns {void}
 */
const initializeEventPreviewMap = async (mapRoot, latitude, longitude) => {
  const mapCanvas = mapRoot.querySelector("[data-event-preview-location-map-canvas]");
  if (!(mapCanvas instanceof HTMLElement) || !mapCanvas.id) {
    return;
  }

  const fallback = mapRoot.querySelector("[data-event-preview-location-map-fallback]");
  const emptyState = mapRoot.querySelector("[data-event-preview-location-empty]");
  setElementHidden(mapCanvas, false);

  try {
    await loadMap(mapCanvas.id, latitude, longitude, {
      interactive: false,
    });
    setElementHidden(fallback, true);
    setElementHidden(emptyState, true);
  } catch (_) {
    setElementHidden(mapCanvas, true);
    setElementHidden(fallback, false);
    setElementHidden(emptyState, false);
  }
};

/**
 * Reads a coordinate from current form fields or the location component seed.
 * @param {Document|Element} pageRoot Event page root.
 * @param {string} fieldName Coordinate field name.
 * @param {string} initialAttribute Coordinate initial value attribute.
 * @returns {number|null} Parsed coordinate.
 */
const readPreviewCoordinate = (pageRoot, fieldName, initialAttribute) => {
  const coordinateField = pageRoot.querySelector?.(`[name="${fieldName}"]`);
  const locationSearchField = pageRoot.querySelector?.("location-search-field");
  if (coordinateField) {
    return parsePreviewCoordinate(coordinateField.value);
  }

  return parsePreviewCoordinate(locationSearchField?.getAttribute(initialAttribute));
};

/**
 * Parses a coordinate from an editor field value.
 * @param {string|undefined} value Coordinate value.
 * @returns {number|null} Parsed coordinate.
 */
const parsePreviewCoordinate = (value) => {
  if (!value) {
    return null;
  }

  const coordinate = Number.parseFloat(value);
  return Number.isFinite(coordinate) ? coordinate : null;
};

/**
 * Renders preview-only sections that come from the current editor state.
 * @param {HTMLElement} modalRoot Modal root element.
 * @param {Document|Element} pageRoot Event page root.
 * @returns {void}
 */
const initializeEventPreviewDraftSections = (modalRoot, pageRoot) => {
  updateEventPreviewTestBadge(modalRoot, pageRoot);
  renderEventPreviewSocialLinks(modalRoot, collectEventPreviewSocialLinks(pageRoot));
  renderEventPreviewTags(modalRoot, collectEventPreviewTags(pageRoot));
};

/**
 * Shows the preview test badge when the current event editor marks it as test.
 * @param {HTMLElement} modalRoot Modal root element.
 * @param {Document|Element} pageRoot Event page root.
 * @returns {void}
 */
const updateEventPreviewTestBadge = (modalRoot, pageRoot) => {
  const badge = modalRoot.querySelector("[data-event-preview-test-badge]");
  if (!(badge instanceof HTMLElement)) {
    return;
  }

  const testEventInput = pageRoot.querySelector?.('[name="test_event"]');
  const testEventToggle = pageRoot.querySelector?.("#toggle_test_event");
  const testEventValue = String(testEventInput?.value || "")
    .trim()
    .toLowerCase();
  const isTestEvent = testEventValue === "true" || testEventToggle?.checked === true;

  setElementHidden(badge, !isTestEvent);
};

/**
 * Collects event social links from the current editor state.
 * @param {Document|Element} pageRoot Event page root.
 * @returns {Array<Object>} Social link data.
 */
const collectEventPreviewSocialLinks = (pageRoot) =>
  EVENT_PREVIEW_SOCIAL_LINKS.map((link) => ({
    ...link,
    url: toOptionalString(pageRoot.querySelector?.(`[name="${link.fieldName}"]`)?.value),
  })).filter((link) => link.url);

/**
 * Renders the event social links section when links are present.
 * @param {HTMLElement} modalRoot Modal root element.
 * @param {Array<Object>} links Social link data.
 * @returns {void}
 */
const renderEventPreviewSocialLinks = (modalRoot, links) => {
  if (links.length === 0) {
    return;
  }

  modalRoot.querySelectorAll("[data-event-preview-social-links]").forEach((container) => {
    if (!(container instanceof HTMLElement)) {
      return;
    }

    const linksList = container.querySelector("[data-event-preview-social-links-list]") || container;
    linksList.replaceChildren(...links.map(createEventPreviewSocialLink));
    if (!container.classList.contains("md:flex")) {
      setElementHidden(container, false);
    }
  });
};

/**
 * Creates a social link using the same classes as the public event page.
 * @param {Object} link Social link data.
 * @param {string} link.iconName Icon name.
 * @param {string} link.platformName Platform name.
 * @param {string} link.url Link URL.
 * @returns {HTMLAnchorElement} Social link.
 */
const createEventPreviewSocialLink = ({ iconName, platformName, url }) => {
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.target = "_blank";
  anchor.rel = "noopener noreferrer";
  anchor.className =
    "group btn-secondary-anchor flex size-[40px] items-center justify-center p-1.5 sm:size-[30px]";
  anchor.title = platformName;

  const icon = document.createElement("div");
  icon.className = `svg-icon size-4 bg-primary-500 transition-colors group-hover:bg-white icon-${iconName}`;
  anchor.append(icon);

  return anchor;
};

/**
 * Collects event tags from the current editor component.
 * @param {Document|Element} pageRoot Event page root.
 * @returns {string[]} Tag labels.
 */
const collectEventPreviewTags = (pageRoot) => {
  const tags = new Set();
  const tagsComponent = pageRoot.querySelector?.('multiple-inputs[field-name="tags"]');

  readArray(tagsComponent?.items).forEach((item) => {
    const tag = typeof item === "object" ? item?.value : item;
    const normalizedTag = toOptionalString(tag);
    if (normalizedTag) {
      tags.add(normalizedTag);
    }
  });

  pageRoot.querySelectorAll?.('[name="tags"], [name="tags[]"]').forEach((field) => {
    const normalizedTag = toOptionalString(field.value);
    if (normalizedTag) {
      tags.add(normalizedTag);
    }
  });

  return [...tags];
};

/**
 * Renders the event tags section when tags are present.
 * @param {HTMLElement} modalRoot Modal root element.
 * @param {string[]} tags Tag labels.
 * @returns {void}
 */
const renderEventPreviewTags = (modalRoot, tags) => {
  const tagsSection = modalRoot.querySelector("[data-event-preview-tags-section]");
  if (!(tagsSection instanceof HTMLElement) || tags.length === 0) {
    return;
  }

  const heading = createEventPreviewSectionHeading("Tags");
  const tagList = document.createElement("div");
  tagList.className = "flex flex-wrap gap-2";

  tags.forEach((tag) => {
    const tagBadge = document.createElement("span");
    tagBadge.className =
      "inline-block max-w-full truncate rounded-full bg-stone-50 px-3 py-1 text-sm uppercase text-stone-700";
    tagBadge.textContent = tag;
    tagList.append(tagBadge);
  });

  tagsSection.replaceChildren(heading, tagList);
  setElementHidden(tagsSection, false);
};

/**
 * Creates a preview section heading matching the public event page.
 * @param {string} text Heading text.
 * @returns {HTMLDivElement} Section heading.
 */
const createEventPreviewSectionHeading = (text) => {
  const heading = document.createElement("div");
  heading.className =
    "pb-8 text-lg font-bold uppercase leading-10 tracking-wide text-stone-900 lg:pb-14 lg:pt-2 lg:text-2xl";
  heading.textContent = text;
  return heading;
};

/**
 * Appends a single form value to the preview payload.
 * @param {URLSearchParams} payload Payload being built.
 * @param {string} name Field name.
 * @param {FormDataEntryValue} value Field value.
 * @returns {void}
 */
const appendPreviewFormValue = (payload, name, value) => {
  if (
    !name ||
    name.startsWith("toggle_") ||
    EVENT_PREVIEW_CLIENT_RENDERED_FIELDS.has(name) ||
    value instanceof File
  ) {
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
  const isEventDate =
    /^(starts_at|ends_at|registration_starts_at|registration_ends_at|cfs_starts_at|cfs_ends_at)$/.test(name);
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

  const parsed = parseJsonAttribute(value, []);
  return Array.isArray(parsed) ? parsed : [];
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
