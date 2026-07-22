/**
 * Credentials tab — CertDirectory integration (stateless / Phase 1).
 *
 * Config (API key per group, badge ID per event) lives in localStorage.
 * Status and issue calls go through the OCG server with X-CD-* headers so
 * attendee emails never reach the browser.
 */

import {
  confirmAction,
  showErrorAlert,
  showSuccessAlert,
} from "/static/js/common/alerts.js";
import {
  initializeMatchingRoots,
  initializeOnReadyAndHtmxLoad,
  markDatasetReady,
} from "/static/js/common/dom.js";
import { ocgFetch } from "/static/js/common/fetch.js";

const ROOT_SELECTOR = "[data-credentials-root]";
const READY_KEY = "credentialsReady";

const apiKeyStorageKey = (groupId) => `cd_api_key:${groupId}`;
const badgeIdStorageKey = (eventId) => `cd_badge_id:${eventId}`;
const badgeNameStorageKey = (eventId) => `cd_badge_name:${eventId}`;

const STATUS_LABELS = {
  not_issued: { text: "Not issued", className: "bg-stone-100 text-stone-600" },
  pending: { text: "Pending", className: "bg-amber-100 text-amber-800" },
  issued: { text: "Issued", className: "bg-emerald-100 text-emerald-800" },
  expired: { text: "Expired", className: "bg-stone-200 text-stone-700" },
  revoked: { text: "Revoked", className: "bg-red-100 text-red-800" },
  failed: { text: "Failed", className: "bg-red-100 text-red-800" },
};

/** True when any credential already exists — Issue must stay disabled. */
const isAlreadyIssued = (status) =>
  status === "issued" ||
  status === "pending" ||
  status === "expired" ||
  status === "revoked";

const escapeHtml = (value) =>
  String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");

const readConfig = (root) => {
  const groupId = root.dataset.groupId;
  const eventId = root.dataset.eventId;
  return {
    apiKey: localStorage.getItem(apiKeyStorageKey(groupId)) || "",
    badgeId: localStorage.getItem(badgeIdStorageKey(eventId)) || "",
    badgeName: localStorage.getItem(badgeNameStorageKey(eventId)) || "",
  };
};

const writeConfig = (root, apiKey, badgeId, badgeName = "") => {
  const groupId = root.dataset.groupId;
  const eventId = root.dataset.eventId;
  if (apiKey) {
    localStorage.setItem(apiKeyStorageKey(groupId), apiKey);
  } else {
    localStorage.removeItem(apiKeyStorageKey(groupId));
  }
  if (badgeId) {
    localStorage.setItem(badgeIdStorageKey(eventId), badgeId);
  } else {
    localStorage.removeItem(badgeIdStorageKey(eventId));
  }
  if (badgeName) {
    localStorage.setItem(badgeNameStorageKey(eventId), badgeName);
  } else {
    localStorage.removeItem(badgeNameStorageKey(eventId));
  }
};

const paintBadgeSummary = (root, badgeName) => {
  const summary = root.querySelector("[data-credentials-badge-summary]");
  const nameEl = root.querySelector("[data-credentials-badge-name]");
  if (!summary || !nameEl) return;
  if (badgeName) {
    nameEl.textContent = badgeName;
    summary.classList.remove("hidden");
  } else {
    nameEl.textContent = "";
    summary.classList.add("hidden");
  }
};

/** Hide the badge summary when the inputs no longer match the last saved pair. */
const syncBadgeSummaryVisibility = (root) => {
  const saved = readConfig(root);
  const { apiKey, badgeId } = readInputValues(root);
  if (saved.apiKey && saved.badgeId && saved.badgeName && apiKey === saved.apiKey && badgeId === saved.badgeId) {
    paintBadgeSummary(root, saved.badgeName);
  } else {
    paintBadgeSummary(root, "");
  }
};

const cdHeaders = (apiKey, badgeId) => ({
  "X-CD-Api-Key": apiKey,
  "X-CD-Badge-Id": badgeId,
});

const readInputValues = (root) => {
  const apiKey = (root.querySelector("[data-credentials-api-key]")?.value || "").trim();
  const badgeId = (root.querySelector("[data-credentials-badge-id]")?.value || "").trim();
  return { apiKey, badgeId };
};

const syncSaveButton = (root) => {
  const saveBtn = root.querySelector("[data-credentials-save]");
  if (!saveBtn) return;
  const { apiKey, badgeId } = readInputValues(root);
  const ready = Boolean(apiKey && badgeId);
  saveBtn.disabled = !ready;
  saveBtn.title = ready
    ? "Validate with CertDirectory and save"
    : "Enter both API key and badge ID";
};

const paintStatus = (row, status, verifyUrl) => {
  const pill = row.querySelector("[data-credentials-status]");
  const verify = row.querySelector("[data-credentials-verify]");
  const issueBtn = row.querySelector("[data-credentials-issue]");
  const meta = STATUS_LABELS[status] || {
    text: status || "—",
    className: "bg-stone-100 text-stone-600",
  };

  if (pill) {
    pill.textContent = meta.text;
    pill.className = `inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium ${meta.className}`;
  }

  if (verify) {
    if (verifyUrl) {
      verify.href = verifyUrl;
      verify.classList.remove("hidden");
    } else {
      verify.classList.add("hidden");
      verify.removeAttribute("href");
    }
  }

  if (issueBtn) {
    const eligible = row.dataset.eligible === "true";
    if (!eligible || isAlreadyIssued(status)) {
      issueBtn.disabled = true;
      issueBtn.title = isAlreadyIssued(status)
        ? "Already issued — re-issue is not available"
        : "Attendee is not eligible";
    } else if (status === "not_issued") {
      issueBtn.disabled = false;
      issueBtn.title = "Issue credential to this attendee";
    } else {
      issueBtn.disabled = true;
    }
  }
};

const hydrateInputs = (root) => {
  const { apiKey, badgeId, badgeName } = readConfig(root);
  const apiKeyInput = root.querySelector("[data-credentials-api-key]");
  const badgeIdInput = root.querySelector("[data-credentials-badge-id]");
  if (apiKeyInput) apiKeyInput.value = apiKey;
  if (badgeIdInput) badgeIdInput.value = badgeId;
  syncSaveButton(root);
  paintBadgeSummary(root, apiKey && badgeId ? badgeName : "");
  return { apiKey, badgeId, badgeName };
};

const setSetupMsg = (root, message, isError = false) => {
  const el = root.querySelector("[data-credentials-setup-msg]");
  if (!el) return;
  el.textContent = message || "";
  el.className = isError
    ? "text-xs text-red-600"
    : "text-xs text-stone-500";
};

const refreshStatus = async (root) => {
  const { apiKey, badgeId } = readInputValues(root);

  if (!apiKey || !badgeId) {
    setSetupMsg(root, "Enter both API key and badge ID, then save / refresh.", true);
    return;
  }

  setSetupMsg(root, "Loading status from CertDirectory…");
  const eventId = root.dataset.eventId;
  try {
    const response = await ocgFetch(
      `/dashboard/group/events/${eventId}/credentials/status`,
      {
        method: "POST",
        credentials: "same-origin",
        headers: cdHeaders(apiKey, badgeId),
      },
    );

    if (!response.ok) {
      const text = (await response.text()) || "Failed to load status";
      setSetupMsg(root, text, true);
      showErrorAlert(text);
      return;
    }

    const rows = await response.json();
    const byUser = new Map(rows.map((r) => [r.user_id, r]));
    root.querySelectorAll("[data-credentials-row]").forEach((row) => {
      const data = byUser.get(row.dataset.userId);
      if (data) {
        paintStatus(row, data.status, data.verify_url);
      } else {
        paintStatus(row, "not_issued", null);
      }
    });
    setSetupMsg(root, "Status loaded.");
  } catch (err) {
    const message = err?.message || "Failed to load status";
    setSetupMsg(root, message, true);
    showErrorAlert(message);
  }
};

/**
 * Re-fetch the Credentials tab HTML (attendee list from OCG) then let init
 * auto-load CertDirectory status. Needed so new RSVPs appear — status-only
 * refresh can only paint rows that are already in the DOM.
 */
const reloadCredentialsPanel = async (root) => {
  const eventId = root.dataset.eventId;
  if (!eventId) return;

  const { apiKey: key, badgeId: badge } = readInputValues(root);
  const saved = readConfig(root);
  if (key && badge) {
    const sameAsSaved = key === saved.apiKey && badge === saved.badgeId;
    writeConfig(root, key, badge, sameAsSaved ? saved.badgeName : "");
  }

  if (!window.htmx || typeof window.htmx.ajax !== "function") {
    await refreshStatus(root);
    return;
  }

  setSetupMsg(root, "Refreshing attendees and status…");
  await window.htmx.ajax(
    "GET",
    `/dashboard/group/events/${eventId}/credentials`,
    {
      target: "#credentials-content",
      swap: "innerHTML",
      indicator: "#dashboard-spinner",
    },
  );
};

/** After HTMX history restore, re-hydrate and re-paint without re-binding. */
const refreshAfterRestore = async (root) => {
  if (!(root instanceof Element)) return;
  hydrateInputs(root);
  const { apiKey, badgeId } = readInputValues(root);
  if (apiKey && badgeId) {
    await refreshStatus(root);
  }
};

const saveAndValidate = async (root) => {
  const saveBtn = root.querySelector("[data-credentials-save]");
  const { apiKey, badgeId } = readInputValues(root);

  if (!apiKey || !badgeId) {
    showErrorAlert("Enter both API key and badge ID.");
    syncSaveButton(root);
    return;
  }

  if (saveBtn) {
    saveBtn.disabled = true;
    saveBtn.textContent = "Validating…";
  }
  setSetupMsg(root, "Validating with CertDirectory…");

  try {
    const response = await ocgFetch(
      `/dashboard/group/events/${root.dataset.eventId}/credentials/validate`,
      {
        method: "POST",
        credentials: "same-origin",
        headers: cdHeaders(apiKey, badgeId),
      },
    );

    if (!response.ok) {
      const text = (await response.text()) || "Validation failed";
      setSetupMsg(root, text, true);
      showErrorAlert(text);
      return;
    }

    const result = await response.json();
    const badgeName = result.badge_name || "Unknown badge";
    const inactiveNote = result.is_active
      ? ""
      : `<br><span class="text-amber-700">Note: this badge is currently inactive.</span>`;

    const confirmed = await confirmAction({
      message: `Save these CertDirectory settings?<br><br><strong>Badge:</strong> ${escapeHtml(badgeName)}${inactiveNote}`,
      confirmText: "Save",
      cancelText: "Cancel",
      withHtml: true,
    });

    if (!confirmed) {
      setSetupMsg(root, "Save cancelled.");
      return;
    }

    writeConfig(root, apiKey, badgeId, badgeName);
    paintBadgeSummary(root, badgeName);
    setSetupMsg(root, `Saved — ${badgeName}`);
    showSuccessAlert(`Saved. Badge: ${badgeName}`);
    await refreshStatus(root);
  } catch (err) {
    const message = err?.message || "Validation failed";
    setSetupMsg(root, message, true);
    showErrorAlert(message);
  } finally {
    if (saveBtn) {
      saveBtn.textContent = "Save to this browser";
      syncSaveButton(root);
    }
  }
};

const issueOne = async (root, row) => {
  const { apiKey, badgeId } = readInputValues(root);
  const userId = row.dataset.userId;
  const issueBtn = row.querySelector("[data-credentials-issue]");

  if (!apiKey || !badgeId) {
    showErrorAlert("Save your API key and badge ID first.");
    return;
  }

  if (issueBtn) {
    issueBtn.disabled = true;
    issueBtn.textContent = "Issuing…";
  }

  try {
    const response = await ocgFetch(
      `/dashboard/group/events/${root.dataset.eventId}/attendees/${userId}/credentials/issue`,
      {
        method: "POST",
        credentials: "same-origin",
        headers: cdHeaders(apiKey, badgeId),
      },
    );

    if (!response.ok) {
      const text = (await response.text()) || "Issue failed";
      showErrorAlert(text);
      if (issueBtn) {
        issueBtn.disabled = false;
        issueBtn.textContent = "Issue";
      }
      return;
    }

    const result = await response.json();
    if (result.error) {
      paintStatus(row, "failed", null);
      showErrorAlert(result.error);
      if (issueBtn) {
        issueBtn.disabled = false;
        issueBtn.textContent = "Issue";
      }
      return;
    }

    paintStatus(row, result.status || "issued", result.verify_url);
    if (issueBtn) issueBtn.textContent = "Issue";
    showSuccessAlert("Credential issued.");
  } catch (err) {
    showErrorAlert(err?.message || "Issue failed");
    if (issueBtn) {
      issueBtn.disabled = false;
      issueBtn.textContent = "Issue";
    }
  }
};

const initCredentialsRoot = (root) => {
  if (!(root instanceof Element) || !markDatasetReady(root, READY_KEY)) {
    return;
  }

  if (root.dataset.canManage !== "true") {
    hydrateInputs(root);
    return;
  }

  const { apiKey, badgeId, badgeName } = hydrateInputs(root);

  root
    .querySelector("[data-credentials-api-key]")
    ?.addEventListener("input", () => {
      syncSaveButton(root);
      syncBadgeSummaryVisibility(root);
    });
  root
    .querySelector("[data-credentials-badge-id]")
    ?.addEventListener("input", () => {
      syncSaveButton(root);
      syncBadgeSummaryVisibility(root);
    });

  root
    .querySelector("[data-credentials-save]")
    ?.addEventListener("click", () => {
      void saveAndValidate(root);
    });

  root
    .querySelector("[data-credentials-refresh]")
    ?.addEventListener("click", () => {
      void reloadCredentialsPanel(root);
    });

  root.querySelectorAll("[data-credentials-issue]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const row = btn.closest("[data-credentials-row]");
      if (row) issueOne(root, row);
    });
  });

  // Auto-load status (and badge name if missing) when both values are already saved.
  if (apiKey && badgeId) {
    void (async () => {
      if (!badgeName) {
        try {
          const response = await ocgFetch(
            `/dashboard/group/events/${root.dataset.eventId}/credentials/validate`,
            {
              method: "POST",
              credentials: "same-origin",
              headers: cdHeaders(apiKey, badgeId),
            },
          );
          if (response.ok) {
            const result = await response.json();
            const name = result.badge_name || "";
            if (name) {
              writeConfig(root, apiKey, badgeId, name);
              paintBadgeSummary(root, name);
            }
          }
        } catch {
          // Non-fatal — status refresh below still runs.
        }
      }
      await refreshStatus(root);
    })();
  } else {
    setSetupMsg(root, "Enter your API key and badge ID to get started.");
  }
};

initializeOnReadyAndHtmxLoad((root, context = {}) => {
  // History restore keeps dataset.credentialsReady, so init is skipped — still
  // re-paint status so Issue buttons are not left disabled.
  if (context.historyRestore) {
    initializeMatchingRoots(root, ROOT_SELECTOR, (el) => {
      void refreshAfterRestore(el);
    });
    return;
  }
  initializeMatchingRoots(root, ROOT_SELECTOR, initCredentialsRoot);
});
