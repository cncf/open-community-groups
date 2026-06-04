import { showInfoAlert } from "/static/js/common/alerts.js";
import {
  consumePendingDeploymentRefreshAlert,
  DEPLOYMENT_REFRESH_MESSAGE,
} from "/static/js/common/deployment-version.js";
import {
  registerHtmxNoEmptyValuesExtensions,
  registerHtmxResponseHandlers,
} from "/static/js/common/htmx-extensions.js";

registerHtmxNoEmptyValuesExtensions(window.htmx);
registerHtmxResponseHandlers(document);

if (consumePendingDeploymentRefreshAlert()) {
  showInfoAlert(DEPLOYMENT_REFRESH_MESSAGE);
}
