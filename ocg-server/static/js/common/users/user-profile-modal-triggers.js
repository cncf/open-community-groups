import { initializeOnReadyAndHtmxLoad } from "/static/js/common/dom.js";
import { parseJsonAttribute, toBoolean } from "/static/js/common/utils.js";
import { dispatchUserModalOpenEvent } from "/static/js/common/users/user-modal-event.js";
import "/static/js/common/modals/user-info-modal.js";

const PROFILE_TRIGGER_SELECTOR = "[data-user-profile-modal]";
let documentTriggersInitialized = false;

/**
 * Ensures delegated profile triggers have a modal host to open.
 * @returns {void}
 */
const ensureUserInfoModal = () => {
  if (document.querySelector("user-info-modal")) {
    return;
  }

  document.body?.append(document.createElement("user-info-modal"));
};

/**
 * Initializes delegated profile modal triggers.
 * @param {Document|Element} root Root element to bind.
 */
export const initUserProfileModalTriggers = (root = document) => {
  ensureUserInfoModal();

  if (root === document) {
    if (documentTriggersInitialized) {
      return;
    }
    documentTriggersInitialized = true;
  } else if (root.dataset?.userProfileModalTriggersReady === "true") {
    return;
  } else {
    if (root.dataset) {
      root.dataset.userProfileModalTriggersReady = "true";
    }
  }

  root.addEventListener("click", handleUserProfileModalClick);
};

/**
 * Opens the user modal for a matching profile trigger click.
 * @param {MouseEvent} event Click event.
 */
export const handleUserProfileModalClick = (event) => {
  if (event.defaultPrevented) {
    return;
  }

  const trigger = event.target?.closest?.(PROFILE_TRIGGER_SELECTOR);
  if (!trigger) {
    return;
  }

  const user = parseJsonAttribute(trigger.getAttribute("data-user-profile"), null);
  if (!user) {
    return;
  }

  event.preventDefault();

  dispatchUserModalOpenEvent(trigger, user, {
    bioIsHtml: toBoolean(trigger.getAttribute("data-user-profile-bio-is-html")),
  });
};

initializeOnReadyAndHtmxLoad(initUserProfileModalTriggers);
