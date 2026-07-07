import { showErrorAlert } from "/static/js/common/alerts.js";
import { markDatasetReady } from "/static/js/common/dom.js";
import { ocgFetch } from "/static/js/common/fetch.js";

/**
 * Initialize check-in toggle checkboxes with optimistic UI updates.
 * @param {Document|Element} [root=document] Query root.
 */
export const initCheckInToggles = (root = document) => {
  root.querySelectorAll(".check-in-toggle").forEach((checkbox) => {
    if (!markDatasetReady(checkbox, "checkInReady")) {
      return;
    }

    checkbox.addEventListener("change", async () => {
      const url = checkbox.dataset.url;
      const label = checkbox.closest("label");

      // Optimistic update: disable and show as checked
      checkbox.disabled = true;
      if (label) {
        label.classList.remove("cursor-pointer");
        label.classList.add("cursor-not-allowed");
      }

      try {
        const response = await ocgFetch(url, {
          credentials: "same-origin",
          method: "POST",
        });
        if (!response.ok) {
          throw new Error("Check-in failed");
        }
      } catch {
        // Revert on error
        checkbox.checked = false;
        checkbox.disabled = false;
        if (label) {
          label.classList.add("cursor-pointer");
          label.classList.remove("cursor-not-allowed");
        }
        showErrorAlert("Failed to check in attendee. Please try again.");
      }
    });
  });
};
