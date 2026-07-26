import { showErrorAlert } from "/static/js/common/alerts.js";
import { closestElementWithinRoot, markDatasetReady } from "/static/js/common/dom.js";
import { ocgFetch } from "/static/js/common/fetch.js";
import {
  closeAttendeeActionsDropdown,
  closeAttendeeBadgeActionsDropdown,
  closeAttendeeEmailActionsDropdown,
  closeAttendeeRowActionMenus,
} from "/static/js/dashboard/group/attendees/actions-menu.js";

const requestControllers = new WeakMap();

/**
 * Initialize attendee badge bypass actions.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
export const initializeAttendeeBadgeAwards = (root = document) => {
  if (!(root instanceof Element) || !markDatasetReady(root, "attendeeBadgeAwardsReady")) {
    return;
  }

  root.addEventListener("click", (event) => {
    const trigger = closestElementWithinRoot(event.target, "[data-attendee-badge-recipients-open]", root);
    if (!(trigger instanceof HTMLButtonElement) || trigger.disabled) return;

    event.preventDefault();
    event.stopPropagation();
    closeAttendeeActionsDropdown(root);
    closeAttendeeBadgeActionsDropdown(root);
    closeAttendeeEmailActionsDropdown(root);
    closeAttendeeRowActionMenus(root);
    openResolvedAttendeeAward(root, trigger);
  });
};

/**
 * Resolve one attendee bypass option and open the shared award modal.
 * @param {Document|Element} root Query root.
 * @param {HTMLButtonElement} trigger Bypass option trigger.
 * @returns {Promise<void>}
 */
const openResolvedAttendeeAward = async (root, trigger) => {
  const eventId = trigger.dataset.eventId || "";
  const scope = trigger.dataset.recipientScope || "";
  if (!eventId || !scope) return;

  requestControllers.get(root)?.abort();
  const controller = new AbortController();
  requestControllers.set(root, controller);
  trigger.disabled = true;
  trigger.setAttribute("aria-busy", "true");

  try {
    const params = new URLSearchParams({ scope });
    const response = await ocgFetch(
      `/dashboard/group/events/${encodeURIComponent(eventId)}/badges/recipients?${params}`,
      { signal: controller.signal },
    );
    if (!response.ok) {
      throw new Error((await response.text()).trim() || "Badge recipients could not be loaded.");
    }
    const output = await response.json();
    const userIds = Array.isArray(output.user_ids) ? output.user_ids : [];
    if (userIds.length === 0) {
      throw new Error("No attendees are eligible for this badge award.");
    }
    document.querySelector("badge-award-modal")?.open({ eventId, trigger, userIds });
  } catch (error) {
    if (error.name !== "AbortError") {
      showErrorAlert(error.message || "Badge recipients could not be loaded.");
    }
  } finally {
    if (requestControllers.get(root) === controller) {
      requestControllers.delete(root);
      if (trigger.isConnected) {
        trigger.disabled = false;
        trigger.removeAttribute("aria-busy");
      }
    }
  }
};
