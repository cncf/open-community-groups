import { confirmAction, showErrorAlert } from "/static/js/common/alerts.js";
import { getElementById, initializeOnReadyAndHtmxLoad, markDatasetReady } from "/static/js/common/dom.js";
import { ocgFetch } from "/static/js/common/fetch.js";

/**
 * Update a sponsor featured toggle loading state.
 * @param {HTMLInputElement} checkbox Toggle input.
 * @param {boolean} loading Whether the toggle should be disabled.
 * @returns {void}
 */
const setSponsorFeaturedToggleLoading = (checkbox, loading) => {
  const label = checkbox.closest("label");

  checkbox.disabled = loading;
  if (label) {
    label.classList.toggle("cursor-pointer", !loading);
    label.classList.toggle("cursor-not-allowed", loading);
  }
};

/**
 * Update a sponsor featured toggle and refresh the dashboard table on success.
 * @param {HTMLInputElement} checkbox
 * @param {boolean} nextChecked
 * @returns {Promise<void>}
 */
const updateSponsorFeatured = async (checkbox, nextChecked) => {
  const url = checkbox.dataset.url;
  const previousChecked = checkbox.dataset.currentChecked === "true";

  checkbox.checked = nextChecked;
  setSponsorFeaturedToggleLoading(checkbox, true);

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
    setSponsorFeaturedToggleLoading(checkbox, false);

    getElementById(document, "dashboard-content")?.dispatchEvent(
      new Event("refresh-group-dashboard-table", {
        bubbles: true,
      }),
    );
  } catch {
    checkbox.checked = previousChecked;
    setSponsorFeaturedToggleLoading(checkbox, false);
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

    if (checkbox.disabled || !markDatasetReady(checkbox, "featuredToggleReady")) {
      return;
    }

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

initializeOnReadyAndHtmxLoad(initializeSponsorsFeatures);
