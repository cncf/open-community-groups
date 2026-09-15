import { showInfoAlert } from "/static/js/common/alerts.js";
import { localizeCurrencyElements } from "/static/js/common/currency.js";
import {
  consumePendingDashboardContextRefreshAlert,
  DASHBOARD_CONTEXT_REFRESH_MESSAGE,
  initializeDashboardContextState,
} from "/static/js/common/dashboard-context.js";
import {
  consumePendingDeploymentRefreshAlert,
  DEPLOYMENT_REFRESH_MESSAGE,
  initializeDeploymentReloadState,
} from "/static/js/common/deployment-version.js";
import { initializeOnReadyAndHtmxLoad } from "/static/js/common/dom.js";
import {
  registerHtmxNoEmptyValuesExtensions,
  registerHtmxResponseHandlers,
} from "/static/js/common/htmx-extensions.js";
import { initializeNavigationState } from "/static/js/common/navigation-state.js";
import "/static/js/common/media/broken-images.js";
import "/static/js/common/profile-completion-alert.js";

// Install request filtering before HTMX builds GET query strings.
registerHtmxNoEmptyValuesExtensions(window.htmx);
// Wire document-level handlers for alerts, 404 swaps, and deployment checks.
registerHtmxResponseHandlers(document);
// Localize currency values on initial render and after HTMX swaps.
initializeOnReadyAndHtmxLoad(localizeCurrencyElements);
// Clear transient dashboard state across HTMX and browser navigation.
initializeNavigationState();
// Release pending reload guards when a page comes back from the back/forward cache.
initializeDashboardContextState();
initializeDeploymentReloadState();

// Show the one-shot notice queued before a deployment-triggered reload.
if (consumePendingDeploymentRefreshAlert()) {
  showInfoAlert(DEPLOYMENT_REFRESH_MESSAGE);
}
// Show the one-shot notice queued before a dashboard context reload.
if (consumePendingDashboardContextRefreshAlert()) {
  showInfoAlert(DASHBOARD_CONTEXT_REFRESH_MESSAGE);
}
