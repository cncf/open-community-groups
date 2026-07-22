import { showInfoAlert } from "/static/js/common/alerts.js";
import {
  consumePendingDeploymentRefreshAlert,
  DEPLOYMENT_REFRESH_MESSAGE,
} from "/static/js/common/deployment-version.js";
import {
  registerHtmxNoEmptyValuesExtensions,
  registerHtmxResponseHandlers,
} from "/static/js/common/htmx-extensions.js";
import { resetRestoredModalState } from "/static/js/common/modals/modal-lifecycle.js";
import "/static/js/common/profile-completion-alert.js";

// Install request filtering before HTMX builds GET query strings.
registerHtmxNoEmptyValuesExtensions(window.htmx);
// Wire document-level handlers for alerts, 404 swaps, and deployment checks.
registerHtmxResponseHandlers(document);

// Show the one-shot notice queued before a deployment-triggered reload.
if (consumePendingDeploymentRefreshAlert()) {
  showInfoAlert(DEPLOYMENT_REFRESH_MESSAGE);
}

// HTMX can restore cached snapshots without running module scripts again.
document.addEventListener("htmx:historyRestore", () => {
  resetRestoredModalState(document);
});

// Native Back/Forward cache restores need the same stale modal cleanup.
window.addEventListener("pageshow", (event) => {
  if (event.persisted) {
    resetRestoredModalState(document);
  }
});
