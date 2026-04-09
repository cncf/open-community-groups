import { mockScrollTo, resetDom, setLocationPath } from "/tests/unit/test-utils/dom.js";
import { mockHtmx, mockSwal } from "/tests/unit/test-utils/globals.js";

/** Clears custom body dataset keys that tests use as one-time listener guards. */
const clearBodyDatasetKeys = (keys = []) => {
  keys.forEach((key) => {
    delete document.body.dataset[key];
  });
};

/** Sets up a dashboard-like browser test environment with common mocks. */
export const setupDashboardTestEnv = ({
  path = "/dashboard/groups",
  withHtmx = false,
  withScroll = false,
  withSwal = false,
  bodyDatasetKeysToClear = [],
} = {}) => {
  const originalPath = window.location.pathname;

  resetDom();
  clearBodyDatasetKeys(bodyDatasetKeysToClear);
  setLocationPath(path);

  const htmx = withHtmx ? mockHtmx() : null;
  const scrollToMock = withScroll ? mockScrollTo() : null;
  const swal = withSwal ? mockSwal() : null;

  return {
    htmx,
    scrollToMock,
    swal,
    restore() {
      clearBodyDatasetKeys(bodyDatasetKeysToClear);
      resetDom();
      htmx?.restore();
      scrollToMock?.restore();
      swal?.restore();
      setLocationPath(originalPath);
    },
  };
};

/** Registers dashboard test env setup and teardown hooks for a suite. */
export const useDashboardTestEnv = (options = {}) => {
  const envRef = {
    current: null,
  };

  beforeEach(() => {
    envRef.current = setupDashboardTestEnv(options);
  });

  afterEach(() => {
    envRef.current?.restore();
    envRef.current = null;
  });

  return envRef;
};
