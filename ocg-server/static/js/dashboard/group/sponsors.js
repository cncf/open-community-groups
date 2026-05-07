import { confirmAction, showErrorAlert } from "/static/js/common/alerts.js";
import { ocgFetch } from "/static/js/common/fetch.js";

/**
 * Update a sponsor featured toggle and refresh the dashboard table on success.
 * @param {HTMLInputElement} checkbox
 * @param {boolean} nextChecked
 * @returns {Promise<void>}
 */
const updateSponsorFeatured = async (checkbox, nextChecked) => {
  const url = checkbox.dataset.url;
  const label = checkbox.closest("label");
  const previousChecked = checkbox.dataset.currentChecked === "true";

  checkbox.checked = nextChecked;
  checkbox.disabled = true;
  if (label) {
    label.classList.remove("cursor-pointer");
    label.classList.add("cursor-not-allowed");
  }

  try {
    const response = await ocgFetch(url, {
      method: "PUT",
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        featured: String(nextChecked),
      }),
    });

    if (!response.ok) {
      throw new Error("Failed to update sponsor visibility");
    }

    checkbox.dataset.currentChecked = String(nextChecked);
    checkbox.disabled = false;
    if (label) {
      label.classList.add("cursor-pointer");
      label.classList.remove("cursor-not-allowed");
    }

    document.getElementById("dashboard-content")?.dispatchEvent(
      new Event("refresh-group-dashboard-table", {
        bubbles: true,
      }),
    );
  } catch {
    checkbox.checked = previousChecked;
    checkbox.disabled = false;
    if (label) {
      label.classList.add("cursor-pointer");
      label.classList.remove("cursor-not-allowed");
    }
    showErrorAlert("Failed to update sponsor visibility. Please try again.");
  }
};

/**
 * Initialize sponsor featured toggles.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
const initializeSponsorFeaturedToggles = (root = document) => {
  root.querySelectorAll?.(".sponsor-featured-toggle").forEach((checkbox) => {
    if (!(checkbox instanceof HTMLInputElement)) {
      return;
    }

    if (checkbox.dataset.featuredToggleReady === "true" || checkbox.disabled) {
      return;
    }

    checkbox.dataset.featuredToggleReady = "true";
    checkbox.dataset.currentChecked = String(checkbox.checked);
    checkbox.addEventListener("change", async () => {
      const previousChecked = checkbox.dataset.currentChecked === "true";
      const nextChecked = checkbox.checked;

      if (previousChecked && !nextChecked) {
        checkbox.checked = previousChecked;
        const confirmed = await confirmAction({
          message: "This sponsor will no longer be visible on the public group page.",
          confirmText: "Continue",
        });

        if (!confirmed) {
          return;
        }
      }

      await updateSponsorFeatured(checkbox, nextChecked);
    });
  });
};

/**
 * Initialize sponsors dashboard interactions.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
const initializeSponsorsFeatures = (root = document) => {
  initializeSponsorFeaturedToggles(root);
};

initializeSponsorsFeatures();

document.addEventListener("htmx:load", (event) => {
  initializeSponsorsFeatures(event.target || document);
});
