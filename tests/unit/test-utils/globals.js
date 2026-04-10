/** Mocks SweetAlert and records every dialog configuration passed to it. */
export const mockSwal = () => {
  const originalSwal = globalThis.Swal;
  const calls = [];
  let nextResult = { isConfirmed: true };

  globalThis.Swal = {
    fire: async (options) => {
      calls.push(options);
      return nextResult;
    },
  };

  return {
    calls,
    setNextResult(result) {
      nextResult = result;
    },
    restore() {
      globalThis.Swal = originalSwal;
    },
  };
};

/** Mocks HTMX ajax and trigger helpers while preserving recorded calls. */
export const mockHtmx = ({ ajaxImpl, triggerImpl } = {}) => {
  const originalHtmx = globalThis.htmx;
  const ajaxCalls = [];
  const triggerCalls = [];

  const htmxMock = {
    ajax: async (...args) => {
      ajaxCalls.push(args);
      return ajaxImpl ? ajaxImpl(...args) : undefined;
    },
    trigger: (...args) => {
      triggerCalls.push(args);
      if (typeof triggerImpl === "function") {
        return triggerImpl(...args);
      }
    },
  };

  globalThis.htmx = htmxMock;

  return {
    ajaxCalls,
    triggerCalls,
    restore() {
      globalThis.htmx = originalHtmx;
    },
  };
};
