import { showInfoAlert } from "/static/js/common/alerts.js";
import {
  consumePendingDeploymentRefreshAlert,
  DEPLOYMENT_REFRESH_MESSAGE,
} from "/static/js/common/deployment-version.js";
import {
  registerHtmxNoEmptyValuesExtensions,
  registerHtmxResponseHandlers,
} from "/static/js/common/htmx-extensions.js";

// Install request filtering before HTMX builds GET query strings.
registerHtmxNoEmptyValuesExtensions(window.htmx);
// Wire document-level handlers for alerts, 404 swaps, and deployment checks.
registerHtmxResponseHandlers(document);

// Show the one-shot notice queued before a deployment-triggered reload.
if (consumePendingDeploymentRefreshAlert()) {
  showInfoAlert(DEPLOYMENT_REFRESH_MESSAGE);
}
