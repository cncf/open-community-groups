import { expect } from "@open-wc/testing";

import { waitForAnimationFrames } from "/tests/unit/test-utils/async.js";
import { resetDom, trackAddedEventListeners } from "/tests/unit/test-utils/dom.js";
import { dispatchHtmxLoad } from "/tests/unit/test-utils/htmx.js";
import { stubMatchMedia } from "/tests/unit/test-utils/media.js";

const DARK_QUERY = "(prefers-color-scheme: dark)";
const LABELS = { dark: "Dark", light: "Light", system: "System" };

/**
 * Renders the account menu theme row with one choice checked, as the header macro does.
 * @param {string} [checked="system"] - Choice rendered with `aria-checked="true"`.
 * @returns {void}
 */
const renderThemeControls = (checked = "system") => {
  document.body.innerHTML = `
    <ul role="group" aria-labelledby="user-menu-theme-label">
      ${["light", "dark", "system"]
        .map(
          (value) => `
            <li role="none">
              <button type="button" role="menuitemradio" aria-checked="${value === checked}" data-ocg-theme-choice="${value}">
                <span id="${value}-icon" class="svg-icon"></span>
                <span id="${value}-label">${LABELS[value]}</span>
              </button>
            </li>`,
        )
        .join("")}
    </ul>
  `;
};

/**
 * Reads the `aria-checked` attribute of every rendered theme choice.
 * @returns {Object<string, string|null>} Attribute values keyed by choice.
 */
const readCheckedState = () =>
  Object.fromEntries(
    [...document.querySelectorAll("[data-ocg-theme-choice]")].map((control) => [
      control.dataset.ocgThemeChoice,
      control.getAttribute("aria-checked"),
    ]),
  );

/**
 * Clicks an element with a bubbling mouse event.
 * @param {string} id - Element id.
 * @returns {void}
 */
const clickElement = (id) => {
  document.getElementById(id).dispatchEvent(new MouseEvent("click", { bubbles: true }));
};

/**
 * Changes the OS color scheme without notifying listeners, as a change missed while the page was
 * frozen or not yet loaded would.
 * @param {boolean} matches - Whether the dark query matches.
 * @returns {void}
 */
const setDarkQuerySilently = (matches) => {
  window.matchMedia(DARK_QUERY).matches = matches;
};

describe("color theme", () => {
  const documentListenerTypes = [];
  const windowListenerTypes = [];
  let THEME_ATTRIBUTE;
  let THEME_CHANGE_EVENT;
  let THEME_MEDIA_QUERY;
  let THEME_PREFERENCES;
  let THEME_STORAGE_KEY;
  let THEME_SWITCHING_ATTRIBUTE;
  let changes;
  let getResolvedTheme;
  let getThemePreference;
  let initTheme;
  let listeners;
  let media;
  let recordChange;
  let resolveTheme;
  let setThemePreference;

  before(async () => {
    // Load the module once under a light OS, recording the listeners it binds.
    media = stubMatchMedia({ [DARK_QUERY]: false });
    listeners = trackAddedEventListeners();
    const trackedDocumentAddEventListener = document.addEventListener;
    const trackedWindowAddEventListener = window.addEventListener;
    document.addEventListener = (type, ...args) => {
      documentListenerTypes.push(type);
      return trackedDocumentAddEventListener(type, ...args);
    };
    window.addEventListener = (type, ...args) => {
      windowListenerTypes.push(type);
      return trackedWindowAddEventListener(type, ...args);
    };
    ({
      THEME_ATTRIBUTE,
      THEME_CHANGE_EVENT,
      THEME_MEDIA_QUERY,
      THEME_PREFERENCES,
      THEME_STORAGE_KEY,
      THEME_SWITCHING_ATTRIBUTE,
      getResolvedTheme,
      getThemePreference,
      initTheme,
      resolveTheme,
      setThemePreference,
    } = await import("/static/js/common/theme.js"));
    document.addEventListener = trackedDocumentAddEventListener;
    window.addEventListener = trackedWindowAddEventListener;
    await waitForAnimationFrames(2);
  });

  beforeEach(() => {
    changes = [];
    recordChange = (event) => changes.push(event.detail);
    document.addEventListener(THEME_CHANGE_EVENT, recordChange);
  });

  afterEach(async () => {
    // Restore the light OS, the System choice and a clean page.
    document.removeEventListener(THEME_CHANGE_EVENT, recordChange);
    media.setMatches(DARK_QUERY, false);
    resetDom();
    setThemePreference("system");
    Object.keys(window.localStorage)
      .filter((key) => key.startsWith("ocg_"))
      .forEach((key) => window.localStorage.removeItem(key));
    await waitForAnimationFrames(2);
  });

  after(() => {
    listeners.restore();
    media.restore();
    document.documentElement.removeAttribute(THEME_ATTRIBUTE);
    document.documentElement.removeAttribute("style");
  });

  it("binds its listeners on load", () => {
    // Verify load attached the delegated, cross-tab, bfcache, HTMX and media listeners.
    expect(windowListenerTypes.toSorted()).to.deep.equal(["pageshow", "storage"]);
    expect(documentListenerTypes).to.include.members(["click", "htmx:historyRestore", "htmx:load"]);
    expect(media.listeners(DARK_QUERY).size).to.equal(1);
  });

  it("resolves light and dark choices and treats anything else as System", () => {
    // Verify each preference under the OS light and dark schemes.
    const cases = [
      ["light", false, "light"],
      ["light", true, "light"],
      ["dark", false, "dark"],
      ["dark", true, "dark"],
      ["system", false, "light"],
      ["system", true, "dark"],
      [null, false, "light"],
      [null, true, "dark"],
      ["sepia", false, "light"],
      ["sepia", true, "dark"],
    ];
    cases.forEach(([preference, prefersDark, theme]) => {
      expect(resolveTheme(preference, prefersDark), `${preference} with dark OS ${prefersDark}`).to.equal(
        theme,
      );
    });
    expect(THEME_PREFERENCES).to.deep.equal(["light", "dark", "system"]);
  });

  it("reads a throwing storage as System", () => {
    const originalGetItem = Storage.prototype.getItem;
    window.localStorage.setItem(THEME_STORAGE_KEY, "dark");
    Storage.prototype.getItem = () => {
      throw new DOMException("Blocked", "SecurityError");
    };

    try {
      // Read and apply the preference while storage throws.
      initTheme();

      // Verify the stored value is ignored and the OS decides.
      expect(getThemePreference()).to.equal("system");
      expect(getResolvedTheme()).to.equal("light");
      expect(document.documentElement.getAttribute(THEME_ATTRIBUTE)).to.equal("light");
    } finally {
      Storage.prototype.getItem = originalGetItem;
    }
  });

  it("stores a dark choice, applies it and announces it once", () => {
    // Choose dark.
    const persisted = setThemePreference("dark");

    // Verify the stored key, the html attribute, the color scheme and the single event.
    expect(persisted).to.equal(true);
    expect(window.localStorage.getItem(THEME_STORAGE_KEY)).to.equal("dark");
    expect(document.documentElement.getAttribute(THEME_ATTRIBUTE)).to.equal("dark");
    expect(document.documentElement.style.colorScheme).to.equal("dark");
    expect(changes).to.deep.equal([{ preference: "dark", previousTheme: "light", theme: "dark" }]);

    // Choose dark again.
    setThemePreference("dark");

    // Verify nothing more is announced and no theme-color meta exists.
    expect(changes).to.have.length(1);
    expect(document.querySelector('meta[name="theme-color"]')).to.equal(null);
  });

  it("removes the key for System and follows the OS, while explicit choices ignore it", () => {
    // Store dark, then return to System under a light OS.
    setThemePreference("dark");
    setThemePreference("system");

    // Verify the key is gone and the OS scheme applies.
    expect(window.localStorage.getItem(THEME_STORAGE_KEY)).to.equal(null);
    expect(document.documentElement.getAttribute(THEME_ATTRIBUTE)).to.equal("light");

    // Switch the OS to dark.
    media.setMatches(DARK_QUERY, true);

    // Verify System follows it live.
    expect(document.documentElement.getAttribute(THEME_ATTRIBUTE)).to.equal("dark");
    expect(document.documentElement.style.colorScheme).to.equal("dark");
    expect(changes.at(-1)).to.deep.equal({ preference: "system", previousTheme: "light", theme: "dark" });

    // Choose light, then flip the OS both ways.
    setThemePreference("light");
    const changeCount = changes.length;
    media.setMatches(DARK_QUERY, false);
    media.setMatches(DARK_QUERY, true);

    // Verify the explicit choice ignores the OS.
    expect(document.documentElement.getAttribute(THEME_ATTRIBUTE)).to.equal("light");
    expect(changes).to.have.length(changeCount);
  });

  it("keeps a choice in memory when storage rejects the write", () => {
    const originalSetItem = Storage.prototype.setItem;
    Storage.prototype.setItem = () => {
      throw new DOMException("Quota exceeded", "QuotaExceededError");
    };

    let persisted;
    try {
      // Choose dark while storage throws.
      persisted = setThemePreference("dark");
    } finally {
      Storage.prototype.setItem = originalSetItem;
    }

    // Verify the choice applies live and is reported as not persisted.
    expect(persisted).to.equal(false);
    expect(window.localStorage.getItem(THEME_STORAGE_KEY)).to.equal(null);
    expect(document.documentElement.getAttribute(THEME_ATTRIBUTE)).to.equal("dark");
    expect(getThemePreference()).to.equal("dark");
    expect(getResolvedTheme()).to.equal("dark");
  });

  it("applies the clicked choice through document delegation", () => {
    // Render the theme row with System checked.
    renderThemeControls();

    // Click the label inside the Dark choice.
    clickElement("dark-label");

    // Verify Dark applies and is the only checked choice.
    expect(document.documentElement.getAttribute(THEME_ATTRIBUTE)).to.equal("dark");
    expect(window.localStorage.getItem(THEME_STORAGE_KEY)).to.equal("dark");
    expect(readCheckedState()).to.deep.equal({ dark: "true", light: "false", system: "false" });

    // Click the icon inside the Light choice.
    clickElement("light-icon");

    // Verify Light applies.
    expect(document.documentElement.getAttribute(THEME_ATTRIBUTE)).to.equal("light");
    expect(readCheckedState()).to.deep.equal({ dark: "false", light: "true", system: "false" });

    // Click the System choice itself.
    document.querySelector('[data-ocg-theme-choice="system"]').click();

    // Verify the key is removed and System is checked again.
    expect(window.localStorage.getItem(THEME_STORAGE_KEY)).to.equal(null);
    expect(readCheckedState()).to.deep.equal({ dark: "false", light: "false", system: "true" });
  });

  it("resyncs server-rendered controls on htmx load and history restore", () => {
    // Choose dark, then swap in a menu rendered with System checked.
    setThemePreference("dark");
    renderThemeControls();

    // Announce the swapped fragment.
    dispatchHtmxLoad(document.querySelector("ul"));

    // Verify the real choice is checked in the markup.
    expect(readCheckedState()).to.deep.equal({ dark: "true", light: "false", system: "false" });

    // Restore a history snapshot that still carries System.
    renderThemeControls();
    document.body.dispatchEvent(new CustomEvent("htmx:historyRestore", { bubbles: true }));

    // Verify the restored markup is resynced through the attribute.
    expect(readCheckedState()).to.deep.equal({ dark: "true", light: "false", system: "false" });
  });

  it("follows another tab's writes and storage clears", () => {
    // Simulate another tab storing dark.
    window.localStorage.setItem(THEME_STORAGE_KEY, "dark");
    window.dispatchEvent(new StorageEvent("storage", { key: THEME_STORAGE_KEY, newValue: "dark" }));

    // Verify the new value applies.
    expect(document.documentElement.getAttribute(THEME_ATTRIBUTE)).to.equal("dark");

    // Simulate a write to an unrelated key while the stored theme changed silently.
    window.localStorage.setItem(THEME_STORAGE_KEY, "light");
    window.dispatchEvent(new StorageEvent("storage", { key: "ocg_viewport_mode", newValue: "desktop" }));

    // Verify unrelated keys are ignored.
    expect(document.documentElement.getAttribute(THEME_ATTRIBUTE)).to.equal("dark");

    // Simulate another tab clearing storage.
    window.localStorage.removeItem(THEME_STORAGE_KEY);
    window.dispatchEvent(new StorageEvent("storage", { key: null }));

    // Verify storage is re-read and System applies.
    expect(document.documentElement.getAttribute(THEME_ATTRIBUTE)).to.equal("light");
    expect(changes.map(({ theme }) => theme)).to.deep.equal(["dark", "light"]);
  });

  it("re-reads storage and the OS only on persisted page shows", () => {
    // Change the OS scheme while the page is frozen.
    setDarkQuerySilently(true);

    // Show the page without a bfcache restore.
    window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: false }));

    // Verify nothing changes.
    expect(document.documentElement.getAttribute(THEME_ATTRIBUTE)).to.equal("light");

    // Restore the page from the bfcache.
    window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: true }));

    // Verify the OS scheme is re-read.
    expect(document.documentElement.getAttribute(THEME_ATTRIBUTE)).to.equal("dark");

    // Store light while frozen, then restore again.
    window.localStorage.setItem(THEME_STORAGE_KEY, "light");
    window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: true }));

    // Verify storage is re-read.
    expect(document.documentElement.getAttribute(THEME_ATTRIBUTE)).to.equal("light");
  });

  it("marks live switches for two animation frames only when the resolved theme changes", async () => {
    const root = document.documentElement;

    /**
     * Runs a change and checks the switching mark against the expectation.
     * @param {() => void} change - Change to apply.
     * @param {boolean} switches - Whether the change alters the resolved theme.
     * @param {string} name - Case name used in assertion messages.
     * @returns {Promise<void>} Resolves once the mark is gone.
     */
    const expectSwitching = async (change, switches, name) => {
      expect(root.hasAttribute(THEME_SWITCHING_ATTRIBUTE), `${name} before`).to.equal(false);
      change();
      expect(root.hasAttribute(THEME_SWITCHING_ATTRIBUTE), name).to.equal(switches);
      await waitForAnimationFrames(2);
      expect(root.hasAttribute(THEME_SWITCHING_ATTRIBUTE), `${name} after two frames`).to.equal(false);
    };

    renderThemeControls();

    // A click that changes the theme, and one that keeps it.
    await expectSwitching(() => clickElement("dark-label"), true, "click to dark");
    await expectSwitching(() => clickElement("dark-label"), false, "click on dark again");

    // A storage event from another tab.
    await expectSwitching(
      () => {
        window.localStorage.setItem(THEME_STORAGE_KEY, "light");
        window.dispatchEvent(new StorageEvent("storage", { key: THEME_STORAGE_KEY }));
      },
      true,
      "storage event",
    );

    // OS changes while System is selected, and while light is chosen.
    setThemePreference("system");
    await expectSwitching(() => media.setMatches(DARK_QUERY, true), true, "media change under System");
    setThemePreference("light");
    await waitForAnimationFrames(2);
    await expectSwitching(() => media.setMatches(DARK_QUERY, false), false, "media change under light");

    // A bfcache restore that finds another stored value.
    await expectSwitching(
      () => {
        window.localStorage.setItem(THEME_STORAGE_KEY, "dark");
        window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: true }));
      },
      true,
      "pageshow restore",
    );

    // The init repair, then an init with nothing to repair.
    await expectSwitching(
      () => {
        window.localStorage.setItem(THEME_STORAGE_KEY, "light");
        initTheme();
      },
      true,
      "init repair",
    );
    await expectSwitching(() => initTheme(), false, "init without repair");
  });

  it("binds each listener once when initialized again", () => {
    const addedTypes = [];
    const trackedDocumentAddEventListener = document.addEventListener;
    const trackedWindowAddEventListener = window.addEventListener;
    document.addEventListener = (type, ...args) => {
      addedTypes.push(type);
      return trackedDocumentAddEventListener(type, ...args);
    };
    window.addEventListener = (type, ...args) => {
      addedTypes.push(type);
      return trackedWindowAddEventListener(type, ...args);
    };

    try {
      // Initialize twice more.
      initTheme();
      initTheme();
    } finally {
      document.addEventListener = trackedDocumentAddEventListener;
      window.addEventListener = trackedWindowAddEventListener;
    }

    // Verify no listener was added.
    expect(addedTypes).to.deep.equal([]);
    expect(media.listeners(DARK_QUERY).size).to.equal(1);

    // Verify one click still applies and announces one change.
    renderThemeControls();
    clickElement("dark-label");
    expect(changes).to.have.length(1);
  });

  it("applies changes made between the inline script and module evaluation", () => {
    // Initialize with nothing changed since the inline script ran.
    initTheme();

    // Verify nothing is announced.
    expect(changes).to.deep.equal([]);

    // Turn the OS dark while System is selected, unnoticed by any listener.
    setDarkQuerySilently(true);
    initTheme();

    // Verify the result applies and is announced once.
    expect(document.documentElement.getAttribute(THEME_ATTRIBUTE)).to.equal("dark");
    expect(changes).to.deep.equal([{ preference: "system", previousTheme: "light", theme: "dark" }]);

    // Simulate another tab storing light before this module ran.
    window.localStorage.setItem(THEME_STORAGE_KEY, "light");
    initTheme();

    // Verify the stored value applies and is announced once.
    expect(document.documentElement.getAttribute(THEME_ATTRIBUTE)).to.equal("light");
    expect(changes).to.deep.equal([
      { preference: "system", previousTheme: "light", theme: "dark" },
      { preference: "light", previousTheme: "dark", theme: "light" },
    ]);
  });

  it("sets the theme when the inline script failed", () => {
    // Simulate a failed inline script.
    document.documentElement.removeAttribute(THEME_ATTRIBUTE);
    document.documentElement.style.removeProperty("color-scheme");

    // Initialize.
    initTheme();

    // Verify the resolved theme and color scheme are applied.
    expect(document.documentElement.getAttribute(THEME_ATTRIBUTE)).to.equal("light");
    expect(document.documentElement.style.colorScheme).to.equal("light");
  });

  it("shares the storage key, attribute and media query with the inline preferences script", async () => {
    // Load the script the base template inlines to apply the color theme before first paint.
    const response = await fetch("/ocg-server/templates/common/scripts/preferences_init.js");
    expect(response.ok).to.equal(true);
    const inlineScript = await response.text();

    // Verify both files agree on the names.
    expect(inlineScript).to.include(`"${THEME_STORAGE_KEY}"`);
    expect(inlineScript).to.include(`"${THEME_ATTRIBUTE}"`);
    expect(inlineScript).to.include(`"${THEME_MEDIA_QUERY}"`);
  });
});
