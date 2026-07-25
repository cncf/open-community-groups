import { showErrorAlert, showSuccessAlert } from "/static/js/common/alerts.js";
import { initializeOnReadyAndHtmxLoad, markDatasetReady } from "/static/js/common/dom.js";
import { ocgFetch } from "/static/js/common/fetch.js";

const CARD_SELECTOR = "[data-badge-card]";
const DRAG_HANDLE_SELECTOR = "[data-badge-drag-handle]";
const LIST_SELECTOR = "[data-badge-order-list]";
const READY_KEY = "badgeControlsReady";
const SAVE_PENDING_KEY = "badgeOrderPending";

const badgeIds = (list) =>
  [...list.querySelectorAll("[data-user-badge-id]")].map((item) => item.dataset.userBadgeId);

const restoreOrder = (list, order) => {
  order.forEach((id) => {
    const item = list.querySelector(`[data-user-badge-id="${CSS.escape(id)}"]`);
    if (item) {
      list.append(item);
    }
  });
};

const announce = (message) => {
  const region = document.getElementById("user-badges-feedback");
  if (region) {
    region.textContent = message;
  }
};

const emptyState = () => {
  const state = document.createElement("div");
  state.className = "rounded-lg border border-dashed border-stone-300 p-10 text-center";
  state.dataset.userBadgesEmpty = "";
  state.innerHTML = `
    <h2 class="font-semibold text-stone-900">No active badges yet</h2>
    <p class="mt-1 text-stone-600">Badges awarded by your groups will appear here.</p>`;
  return state;
};

const clearDragStyles = (list) => {
  list.querySelectorAll("[data-user-badge-id]").forEach((item) => {
    item.classList.remove("opacity-70");
    item.querySelector(CARD_SELECTOR)?.classList.remove("ring-2", "ring-primary-300");
  });
};

const syncReorderControls = (list) => {
  const items = [...list.querySelectorAll("[data-user-badge-id]")];
  const pending = list.dataset[SAVE_PENDING_KEY] === "true";
  items.forEach((item, index) => {
    const handle = item.querySelector(DRAG_HANDLE_SELECTOR);
    const position = item.querySelector("[data-badge-position]");
    if (handle) {
      handle.disabled = pending || items.length <= 1;
      handle.draggable = !handle.disabled;
    }
    if (position) {
      position.textContent = String(index + 1);
    }
    item.querySelectorAll("[data-badge-move]").forEach((button) => {
      const atBoundary = button.dataset.badgeMove === "up" ? index === 0 : index === items.length - 1;
      button.disabled = pending || atBoundary;
    });
  });
};

/**
 * Persist the visible badge order and restore it if saving fails.
 * @param {HTMLOListElement} list Badge order list.
 * @param {Array<string>} previousOrder Badge IDs before reordering.
 * @returns {Promise<boolean>} Whether the order was saved.
 */
export const persistOrder = async (list, previousOrder) => {
  if (list.dataset[SAVE_PENDING_KEY] === "true") {
    return false;
  }
  list.dataset[SAVE_PENDING_KEY] = "true";
  syncReorderControls(list);
  try {
    const response = await ocgFetch("/dashboard/user/badges/order", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ user_badge_ids: badgeIds(list) }),
    });
    if (!response.ok) {
      throw new Error("Badge order was not saved.");
    }
    announce("Badge order saved.");
    showSuccessAlert("Badge order saved.");
    return true;
  } catch (error) {
    restoreOrder(list, previousOrder);
    throw error;
  } finally {
    delete list.dataset[SAVE_PENDING_KEY];
    syncReorderControls(list);
  }
};

/**
 * Move a badge one position with a keyboard or fallback button control.
 * @param {HTMLElement} control Reorder control inside the badge card.
 * @param {"up"|"down"} direction Direction to move the badge.
 * @returns {Promise<void>}
 */
export const moveBadge = async (control, direction = control.dataset.badgeMove) => {
  const item = control.closest("[data-user-badge-id]");
  const list = item?.closest(LIST_SELECTOR);
  if (!item || !list) {
    return;
  }
  if (list.dataset[SAVE_PENDING_KEY] === "true") {
    return;
  }
  const previousOrder = badgeIds(list);
  const sibling = direction === "up" ? item.previousElementSibling : item.nextElementSibling;
  if (!sibling) {
    return;
  }
  if (direction === "up") {
    list.insertBefore(item, sibling);
  } else {
    list.insertBefore(sibling, item);
  }
  control.focus();
  try {
    await persistOrder(list, previousOrder);
  } catch (error) {
    showErrorAlert(error.message);
  }
};

/**
 * Save whether a badge is shown on the user's public profile.
 * @param {HTMLInputElement} control Profile listing checkbox.
 * @returns {Promise<void>}
 */
export const updateListing = async (control) => {
  const previousValue = !control.checked;
  control.disabled = true;
  try {
    const response = await ocgFetch(control.dataset.endpoint, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ is_listed: control.checked }),
    });
    if (!response.ok) {
      throw new Error("Profile listing was not saved.");
    }
    announce("Profile listing saved.");
    showSuccessAlert("Profile listing saved.");
  } catch (error) {
    control.checked = previousValue;
    showErrorAlert(error.message);
  } finally {
    control.disabled = false;
  }
};

/**
 * Permanently revoke a badge after the user confirms the destructive action.
 * @param {HTMLButtonElement} button Badge revoke control.
 * @returns {Promise<void>}
 */
export const revokeBadge = async (button) => {
  if (button.disabled) {
    return;
  }
  const result = await Swal.fire({
    title: `Permanently revoke ${button.dataset.badgeName}?`,
    text: "This cannot be undone. If you only want to remove it from your profile, cancel and turn off Show on profile instead.",
    icon: "warning",
    showCancelButton: true,
    confirmButtonText: "Permanently revoke",
    cancelButtonText: "Cancel",
    focusCancel: true,
  });
  if (!result.isConfirmed) {
    button.focus();
    return;
  }

  button.disabled = true;
  try {
    const response = await ocgFetch(button.dataset.endpoint, { method: "DELETE" });
    if (!response.ok) {
      throw new Error("The badge could not be revoked.");
    }
    const list = button.closest(LIST_SELECTOR);
    button.closest("[data-user-badge-id]")?.remove();
    if (list) {
      if (list.querySelector("[data-user-badge-id]")) {
        syncReorderControls(list);
      } else {
        list.replaceWith(emptyState());
      }
    }
    announce("Badge permanently revoked.");
    showSuccessAlert("Badge permanently revoked.");
  } catch (error) {
    button.disabled = false;
    showErrorAlert(error.message);
  }
};

/**
 * Initialize listing, reorder, and revoke controls for a badge list.
 * @param {HTMLOListElement} list Badge order list.
 * @returns {void}
 */
export const initializeBadgeList = (list) => {
  if (!markDatasetReady(list, READY_KEY)) {
    return;
  }

  let draggedItem = null;
  let dropTargetItem = null;
  let previousOrder = [];
  syncReorderControls(list);
  list.addEventListener("click", (event) => {
    const moveButton = event.target.closest?.("[data-badge-move]");
    if (moveButton) {
      moveBadge(moveButton);
      return;
    }
    const revokeButton = event.target.closest?.("[data-badge-revoke]");
    if (revokeButton) {
      revokeBadge(revokeButton);
    }
  });
  list.addEventListener("change", (event) => {
    if (event.target.matches?.("[data-badge-listing]")) {
      updateListing(event.target);
    }
  });
  list.addEventListener("keydown", (event) => {
    const dragHandle = event.target.closest?.(DRAG_HANDLE_SELECTOR);
    if (!dragHandle || dragHandle.disabled) {
      return;
    }
    if (event.key !== "ArrowUp" && event.key !== "ArrowDown") {
      return;
    }
    event.preventDefault();
    moveBadge(dragHandle, event.key === "ArrowUp" ? "up" : "down");
  });
  list.addEventListener("dragstart", (event) => {
    if (list.dataset[SAVE_PENDING_KEY] === "true") {
      event.preventDefault();
      return;
    }
    const dragHandle = event.target.closest?.(DRAG_HANDLE_SELECTOR);
    draggedItem = dragHandle?.closest("[data-user-badge-id]") || null;
    if (draggedItem) {
      previousOrder = badgeIds(list);
      draggedItem.classList.add("opacity-70");
      if (event.dataTransfer) {
        event.dataTransfer.effectAllowed = "move";
        event.dataTransfer.setData?.("text/plain", draggedItem.dataset.userBadgeId);
        event.dataTransfer.setDragImage?.(dragHandle, 0, 0);
      }
    }
  });
  list.addEventListener("dragover", (event) => {
    const target = event.target.closest?.("[data-user-badge-id]");
    if (!draggedItem || !target || target === draggedItem) {
      return;
    }
    event.preventDefault();
    if (dropTargetItem !== target) {
      dropTargetItem?.querySelector(CARD_SELECTOR)?.classList.remove("ring-2", "ring-primary-300");
      dropTargetItem = target;
      dropTargetItem.querySelector(CARD_SELECTOR)?.classList.add("ring-2", "ring-primary-300");
    }
    const before = event.clientY < target.getBoundingClientRect().top + target.offsetHeight / 2;
    list.insertBefore(draggedItem, before ? target : target.nextElementSibling);
    syncReorderControls(list);
  });
  list.addEventListener("dragend", async () => {
    clearDragStyles(list);
    dropTargetItem = null;
    if (!draggedItem || previousOrder.join() === badgeIds(list).join()) {
      draggedItem = null;
      return;
    }
    draggedItem = null;
    try {
      await persistOrder(list, previousOrder);
    } catch (error) {
      showErrorAlert(error.message);
    }
  });
};

initializeOnReadyAndHtmxLoad((root) => {
  if (root.matches?.(LIST_SELECTOR)) {
    initializeBadgeList(root);
  }
  root.querySelectorAll?.(LIST_SELECTOR).forEach(initializeBadgeList);
});
