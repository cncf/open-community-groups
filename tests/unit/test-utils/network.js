/** Mocks fetch and records each request made by the code under test. */
export const mockFetch = ({ impl, response } = {}) => {
  const originalFetch = globalThis.fetch;
  const calls = [];
  let currentImpl = impl;

  globalThis.fetch = async (...args) => {
    calls.push(args);
    if (typeof currentImpl === "function") {
      return currentImpl(...args);
    }
    if (response !== undefined) {
      return response;
    }
    return { ok: true, status: 200 };
  };

  return {
    calls,
    setImpl(nextImpl) {
      currentImpl = nextImpl;
    },
    restore() {
      globalThis.fetch = originalFetch;
    },
  };
};

/** Mocks history.pushState and records every navigation update request. */
export const mockPushState = ({ impl } = {}) => {
  const originalPushState = window.history.pushState.bind(window.history);
  const calls = [];

  window.history.pushState = (...args) => {
    calls.push(args);
    if (typeof impl === "function") {
      return impl(...args);
    }
  };

  return {
    calls,
    restore() {
      window.history.pushState = originalPushState;
    },
  };
};

/** Mocks sendBeacon with a configurable return value and captured payloads. */
export const mockSendBeacon = (returnValue = true) => {
  const originalSendBeacon = navigator.sendBeacon;
  const calls = [];
  let currentReturnValue = returnValue;

  navigator.sendBeacon = (endpoint, payload) => {
    calls.push({ endpoint, payload });
    return currentReturnValue;
  };

  return {
    calls,
    setReturnValue(nextValue) {
      currentReturnValue = nextValue;
    },
    restore() {
      if (originalSendBeacon) {
        navigator.sendBeacon = originalSendBeacon;
      } else {
        delete navigator.sendBeacon;
      }
    },
  };
};

/** Mocks document.visibilityState with a mutable value for page lifecycle tests. */
export const mockVisibilityState = (initialValue = "visible") => {
  const originalVisibilityState = Object.getOwnPropertyDescriptor(Document.prototype, "visibilityState");
  let currentValue = initialValue;

  Object.defineProperty(document, "visibilityState", {
    configurable: true,
    get: () => currentValue,
  });

  return {
    get value() {
      return currentValue;
    },
    set(nextValue) {
      currentValue = nextValue;
    },
    restore() {
      if (originalVisibilityState) {
        Object.defineProperty(Document.prototype, "visibilityState", originalVisibilityState);
      }
      delete document.visibilityState;
    },
  };
};
