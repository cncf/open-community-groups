/**
 * Replaces window.matchMedia with doubles that answer only the listed queries.
 *
 * Each query text gets one double, created on first use and kept for the life
 * of the stub, so modules that subscribe once keep receiving changes. Unknown
 * queries answer false, so a test fails when code reads a breakpoint it did not
 * expect. Install the stub before importing a module that reads matchMedia on
 * load, and keep that one stub for the module's life: a second stub hands later
 * reads a new double while the module's listener stays on the old one.
 * @param {Object<string, boolean>} [states={}] Initial matches per query text.
 * @returns {{calls: string[], listeners: (query: string) => Set<Function>,
 *   restore: () => void, setMatches: (query: string, matches: boolean) => void}} Controls.
 */
export const stubMatchMedia = (states = {}) => {
  const calls = [];
  const doubles = new Map();
  const previousMatchMedia = window.matchMedia;

  const doubleFor = (query) => {
    if (!doubles.has(query)) {
      const listeners = new Set();
      doubles.set(query, {
        listeners,
        media: {
          addEventListener: (type, listener) => {
            if (type === "change") {
              listeners.add(listener);
            }
          },
          matches: Boolean(states[query]),
          media: query,
          removeEventListener: (type, listener) => {
            if (type === "change") {
              listeners.delete(listener);
            }
          },
        },
      });
    }
    return doubles.get(query);
  };

  window.matchMedia = (query) => {
    calls.push(query);
    return doubleFor(query).media;
  };

  return {
    calls,
    listeners: (query) => doubleFor(query).listeners,
    restore: () => {
      window.matchMedia = previousMatchMedia;
    },
    setMatches: (query, matches) => {
      const { listeners, media } = doubleFor(query);
      media.matches = matches;
      [...listeners].forEach((listener) => listener({ matches, media: query }));
    },
  };
};
