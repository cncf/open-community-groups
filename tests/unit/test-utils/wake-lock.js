/**
 * Replaces the Screen Wake Lock API with a double that records its locks.
 * @returns {{locks: object[], requests: string[], reject: (error: Error) => void, restore: () => void}}
 *   Recorded locks and requests, the next-request failure switch, and the cleanup.
 */
export const mockWakeLock = () => {
  const locks = [];
  const requests = [];
  let nextError = null;

  Object.defineProperty(navigator, "wakeLock", {
    configurable: true,
    value: {
      request: async (type) => {
        requests.push(type);
        if (nextError) {
          const error = nextError;
          nextError = null;
          throw error;
        }
        const lock = {
          release: async () => {
            lock.released = true;
          },
          released: false,
        };
        locks.push(lock);
        return lock;
      },
    },
  });

  return {
    locks,
    reject: (error) => {
      nextError = error;
    },
    requests,
    restore: () => {
      delete navigator.wakeLock;
    },
  };
};

/**
 * Replaces matchMedia with a phone query whose state tests can change.
 * @param {string} phoneQuery Query text that the double answers.
 * @param {boolean} matches Initial state.
 * @returns {{listeners: Set<Function>, restore: () => void, setMatches: (next: boolean) => void}} Controls.
 */
export const mockPhoneMedia = (phoneQuery, matches) => {
  const listeners = new Set();
  const originalMatchMedia = window.matchMedia;
  const query = {
    addEventListener: (type, listener) => {
      if (type === "change") {
        listeners.add(listener);
      }
    },
    matches,
    removeEventListener: (type, listener) => {
      if (type === "change") {
        listeners.delete(listener);
      }
    },
  };

  window.matchMedia = (text) => (text === phoneQuery ? query : { matches: false });

  return {
    listeners,
    restore: () => {
      window.matchMedia = originalMatchMedia;
    },
    setMatches: (next) => {
      query.matches = next;
      [...listeners].forEach((listener) => listener({ matches: next }));
    },
  };
};

/**
 * Sets the page visibility and announces the change.
 * @param {"hidden"|"visible"} state New visibility state.
 * @returns {void}
 */
export const setPageVisibility = (state) => {
  Object.defineProperty(document, "visibilityState", { configurable: true, value: state });
  document.dispatchEvent(new Event("visibilitychange"));
};

/**
 * Restores the real page visibility.
 * @returns {void}
 */
export const restorePageVisibility = () => {
  delete document.visibilityState;
};
