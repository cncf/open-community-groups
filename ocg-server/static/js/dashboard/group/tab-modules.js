import { initializeOnReady } from "/static/js/common/dom.js";

const DASHBOARD_SPINNER_SELECTOR = "#dashboard-spinner";
const GROUP_DASHBOARD_PREFIX = "/dashboard/group";
const GROUP_DASHBOARD_SCOPE_SELECTOR = "[data-ocg-selected-group-id]";

// Maps group dashboard module group keys to lazy dynamic import loaders.
// Each loader uses literal paths so build.rs rewrites them to hashed asset URLs.
const MODULE_GROUP_LOADERS = {
  attendees: () =>
    Promise.all([
      import("/static/js/dashboard/group/attendees.js"),
      import("/static/js/dashboard/group/badge-award-modal.js"),
      import("/static/js/dashboard/group/check-in/scanner.js"),
    ]),
  "audit-logs": () => import("/static/js/dashboard/audit-logs.js"),
  badges: () => import("/static/js/dashboard/group/badges.js"),
  "badges-artwork": () =>
    Promise.all([
      import("/static/js/common/media/image-field.js"),
      import("/static/js/dashboard/group/badges.js"),
    ]),
  "check-in": () => import("/static/js/dashboard/group/check-in/scanner.js"),
  cohosts: () => import("/static/js/dashboard/group/cohosts.js"),
  "event-add": () => import("/static/js/dashboard/group/event-add.js"),
  "event-requests": () =>
    Promise.all([
      import("/static/js/common/users/user-profile-modal-triggers.js"),
      import("/static/js/dashboard/group/events-list.js"),
    ]),
  "event-submissions": () => import("/static/js/dashboard/event/cfs/actions.js"),
  "event-update": () => import("/static/js/dashboard/group/event-update.js"),
  "events-list": () => import("/static/js/dashboard/group/events-list.js"),
  inbox: () => import("/static/js/common/media/logo-image.js"),
  members: () =>
    Promise.all([
      import("/static/js/common/media/logo-image.js"),
      import("/static/js/dashboard/group/members.js"),
    ]),
  refunds: () =>
    Promise.all([
      import("/static/js/common/media/logo-image.js"),
      import("/static/js/dashboard/group/refunds.js"),
    ]),
  settings: () =>
    Promise.all([
      import("/static/js/dashboard/form-page-elements.js"),
      import("/static/js/dashboard/group/settings-form.js"),
      import("/static/js/dashboard/location-clear.js"),
    ]),
  "sponsor-form": () => import("/static/js/common/media/image-field.js"),
  "sponsors-list": () => import("/static/js/dashboard/group/sponsors.js"),
  "survey-responses": () => import("/static/js/common/media/logo-image.js"),
  team: () =>
    Promise.all([
      import("/static/js/dashboard/community/team-add-member.js"),
      import("/static/js/dashboard/group/badge-award-modal.js"),
      import("/static/js/dashboard/team-role-form.js"),
    ]),
};

const PRELOADING_ATTRIBUTE = "data-ocg-preloading";

const SUBPATH_RULES = [
  { group: "settings", pattern: /^\/settings\/update$/ },
  { group: "team", pattern: /^\/team$/ },
  { group: "inbox", pattern: /^\/inbox(?:\/[^/]+)?$/ },
  { group: "audit-logs", pattern: /^\/logs$/ },
  { group: "events-list", pattern: /^\/events$/ },
  { group: "event-add", pattern: /^\/events\/add$/ },
  { group: "event-update", pattern: /^\/events\/[^/]+\/update$/ },
  { group: "attendees", pattern: /^\/events\/[^/]+\/attendees$/ },
  { group: "event-submissions", pattern: /^\/events\/[^/]+\/submissions$/ },
  { group: "event-requests", pattern: /^\/events\/[^/]+\/(?:invitation-requests|waitlist)$/ },
  { group: "survey-responses", pattern: /^\/events\/[^/]+\/surveys\/[^/]+\/responses$/ },
  { group: "check-in", pattern: /^\/check-in$/ },
  { group: "cohosts", pattern: /^\/cohosts$/ },
  { group: "refunds", pattern: /^\/refunds$/ },
  { group: "badges", pattern: /^\/(?:badges|awards)$/ },
  { group: "badges-artwork", pattern: /^\/artwork$/ },
  { group: "members", pattern: /^\/members$/ },
  { group: "sponsors-list", pattern: /^\/sponsors$/ },
  { group: "sponsor-form", pattern: /^\/sponsors\/(?:add|[^/]+\/update)$/ },
];

const TAB_TO_MODULE_GROUP = {
  artwork: "badges-artwork",
  awards: "badges",
  badges: "badges",
  "check-in": "check-in",
  cohosts: "cohosts",
  events: "events-list",
  inbox: "inbox",
  logs: "audit-logs",
  members: "members",
  refunds: "refunds",
  settings: "settings",
  sponsors: "sponsors-list",
  team: "team",
};

const inflightGroupLoads = new Map();
const initializedTargets = new WeakSet();
const loadedGroups = new Set();

/**
 * Preloads tab- and section-scoped group dashboard modules before HTMX swaps in
 * the target fragment, preventing clicks on newly swapped controls from racing
 * ahead of async module evaluation.
 *
 * Defaults to listening on `window` so `document`-level `htmx:confirm` guards
 * (such as unsaved-survey-changes prompts) run first and set `defaultPrevented`.
 * @param {EventTarget} [eventTarget=window] Event listener target.
 * @param {object} [options={}] Optional loader overrides for testing.
 * @param {(groupKey: string) => Promise<void>} [options.loadGroup] Custom module group loader.
 * @param {Set<string>} [options.loaded] Tracking set of already-loaded module group keys.
 * @returns {() => void} Cleanup callback removing the listener.
 */
export const initializeGroupDashboardTabModules = (
  eventTarget = window,
  { loadGroup = loadModuleGroup, loaded = loadedGroups } = {},
) => {
  if (initializedTargets.has(eventTarget)) {
    return () => {};
  }

  initializedTargets.add(eventTarget);
  const pendingNavigations = new Map();
  const retriedElements = new WeakSet();

  const warmGroup = (groupKey) => {
    if (groupKey && !loaded.has(groupKey)) {
      void runGroupLoader(loadGroup, groupKey, loaded).catch(() => {});
    }
  };

  const handleConfirm = (event) => {
    const detail = event.detail;
    if (!detail || detail.question || detail.verb?.toLowerCase() !== "get") {
      return;
    }

    // Do nothing once the user has navigated away from the group dashboard shell.
    if (!document.querySelector(GROUP_DASHBOARD_SCOPE_SELECTOR)) {
      return;
    }

    const groupKey = resolveGroupDashboardModuleGroup(detail.path);
    const target = detail.target instanceof Element ? detail.target : null;
    const requestElement = detail.elt;

    // A document-level guard already held this event (e.g. unsaved survey edits);
    // warm the module in the background without issuing or cancelling anything.
    if (event.defaultPrevented) {
      warmGroup(groupKey);
      return;
    }

    // Invalidate older pending preloads targeting the same or nested containers
    // without letting an inner background refresh cancel an outer tab navigation.
    if (cancelSupersededNavigations(pendingNavigations, target)) {
      syncDashboardSpinner(pendingNavigations.size);
    }

    // Never cancel programmatic `htmx.ajax()` calls whose callers await the returned
    // promise; start preloading in parallel instead.
    if (detail.etc?.returnPromise) {
      warmGroup(groupKey);
      return;
    }

    // Skip re-entering during our own post-preload `htmx:confirm` re-check.
    if (requestElement instanceof Element && retriedElements.has(requestElement)) {
      return;
    }

    if (!groupKey || loaded.has(groupKey) || typeof detail.issueRequest !== "function") {
      return;
    }

    event.preventDefault();
    const token = Symbol(groupKey);
    pendingNavigations.set(token, target);
    syncDashboardSpinner(pendingNavigations.size);

    runGroupLoader(loadGroup, groupKey, loaded)
      .catch((error) => {
        // Proceed with the swap even on preload failure so the partial's script tag can retry.
        console.error(`Failed to preload group dashboard module group "${groupKey}":`, error);
      })
      .finally(() => {
        if (!pendingNavigations.has(token)) {
          return;
        }
        pendingNavigations.delete(token);
        syncDashboardSpinner(pendingNavigations.size);
        if (requestElement instanceof Node && !requestElement.isConnected) {
          return;
        }

        // Re-run `htmx:confirm` guards (such as unsaved-survey prompts) because HTMX's
        // `issueRequest()` skips `htmx:confirm`, and the form may have become dirty during preload.
        if (requestElement instanceof Element) {
          retriedElements.add(requestElement);
          let allowed = true;
          try {
            const reconfirmEvent = new CustomEvent("htmx:confirm", {
              bubbles: true,
              cancelable: true,
              detail,
            });
            allowed = requestElement.dispatchEvent(reconfirmEvent);
          } finally {
            retriedElements.delete(requestElement);
          }
          if (!allowed) {
            return;
          }
        }
        detail.issueRequest(true);
      });
  };

  eventTarget.addEventListener("htmx:confirm", handleConfirm);
  return () => {
    eventTarget.removeEventListener("htmx:confirm", handleConfirm);
    pendingNavigations.clear();
    syncDashboardSpinner(0);
    initializedTargets.delete(eventTarget);
  };
};

/**
 * Loads a module group once, deduplicating concurrent requests for the same key.
 * @param {string} groupKey Module group key.
 * @returns {Promise<void>} Resolves once all modules in the group finish evaluating.
 */
export const loadModuleGroup = (groupKey) => {
  if (loadedGroups.has(groupKey)) {
    return Promise.resolve();
  }

  const existingLoad = inflightGroupLoads.get(groupKey);
  if (existingLoad) {
    return existingLoad;
  }

  const loader = MODULE_GROUP_LOADERS[groupKey];
  if (!loader) {
    return Promise.resolve();
  }

  const pendingLoad = Promise.resolve()
    .then(() => loader())
    .then(() => {
      loadedGroups.add(groupKey);
    })
    .finally(() => {
      inflightGroupLoads.delete(groupKey);
    });

  inflightGroupLoads.set(groupKey, pendingLoad);
  return pendingLoad;
};

/**
 * Resolves the module group key required for a group dashboard GET URL.
 * @param {string|null|undefined} path Request URL or path.
 * @returns {string|null} Module group key, or null when no lazy group applies.
 */
export const resolveGroupDashboardModuleGroup = (path) => {
  if (typeof path !== "string" || !path.trim()) {
    return null;
  }

  let parsedUrl;
  try {
    parsedUrl = new URL(path, window.location.origin);
  } catch {
    return null;
  }

  const pathname = parsedUrl.pathname.replace(/\/+$/, "") || "/";
  if (pathname === GROUP_DASHBOARD_PREFIX) {
    const tab = (parsedUrl.searchParams.get("tab") || "settings").trim();
    return Object.hasOwn(TAB_TO_MODULE_GROUP, tab) ? TAB_TO_MODULE_GROUP[tab] : null;
  }

  if (!pathname.startsWith(`${GROUP_DASHBOARD_PREFIX}/`)) {
    return null;
  }

  const subpath = pathname.slice(GROUP_DASHBOARD_PREFIX.length);
  for (const rule of SUBPATH_RULES) {
    if (rule.pattern.test(subpath)) {
      return rule.group;
    }
  }

  return null;
};

/**
 * Cancels pending preloads whose target equals or sits inside the incoming navigation target.
 * Inner background refreshes (for example `#dashboard-content`) never cancel an outer
 * `#dashboard-layout` tab click.
 * @param {Map<symbol, Element|null>} pendingNavigations Active pending navigations.
 * @param {Element|null} target Target element of the incoming navigation.
 * @returns {boolean} True when at least one pending preload was cancelled.
 */
const cancelSupersededNavigations = (pendingNavigations, target) => {
  if (!target) {
    return false;
  }

  let cancelled = false;
  for (const [pendingToken, pendingTarget] of pendingNavigations.entries()) {
    if (pendingTarget && (pendingTarget === target || target.contains(pendingTarget))) {
      pendingNavigations.delete(pendingToken);
      cancelled = true;
    }
  }
  return cancelled;
};

/**
 * Runs a group loader immediately and records completion in `loaded` on success.
 * @param {(groupKey: string) => Promise<void>} loadGroup Loader callback.
 * @param {string} groupKey Module group key.
 * @param {Set<string>} loaded Tracking set of loaded group keys.
 * @returns {Promise<void>} Resolves once loading finishes.
 */
const runGroupLoader = (loadGroup, groupKey, loaded) => {
  try {
    return Promise.resolve(loadGroup(groupKey)).then(() => {
      loaded.add(groupKey);
    });
  } catch (error) {
    return Promise.reject(error);
  }
};

/**
 * Marks or clears the dashboard spinner preload indicator independently of HTMX's own
 * `htmx-request` class so superseded preloads never hide an active XHR's spinner.
 * @param {number} count Active preload count.
 * @returns {void}
 */
const syncDashboardSpinner = (count) => {
  const spinner = document.querySelector(DASHBOARD_SPINNER_SELECTOR);
  if (!spinner) {
    return;
  }
  if (count > 0) {
    spinner.setAttribute(PRELOADING_ATTRIBUTE, "true");
  } else {
    spinner.removeAttribute(PRELOADING_ATTRIBUTE);
  }
};

initializeOnReady(() => initializeGroupDashboardTabModules(window));
