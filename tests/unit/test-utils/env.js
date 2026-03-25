import { mockScrollTo, resetDom, setLocationPath } from "/tests/unit/test-utils/dom.js";
import { mockHtmx, mockSwal } from "/tests/unit/test-utils/globals.js";

/** Sets up a dashboard-like browser test environment with common mocks. */
export const setupDashboardTestEnv = ({
  path = "/dashboard/groups",
  withHtmx = false,
  withScroll = false,
  withSwal = false,
} = {}) => {
  const originalPath = window.location.pathname;

  resetDom();
  setLocationPath(path);

  const htmx = withHtmx ? mockHtmx() : null;
  const scrollToMock = withScroll ? mockScrollTo() : null;
  const swal = withSwal ? mockSwal() : null;

  return {
    htmx,
    scrollToMock,
    swal,
    restore() {
      resetDom();
      htmx?.restore();
      scrollToMock?.restore();
      swal?.restore();
      setLocationPath(originalPath);
    },
  };
};
