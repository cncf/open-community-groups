import { getCommonAlertOptions } from "/static/js/common/alerts.js";
import { initializeOnReadyAndHtmxLoad } from "/static/js/common/dom.js";

export const PROFILE_COMPLETION_URL = "/dashboard/user?tab=account";

const PROFILE_COMPLETION_MESSAGE =
  "Complete your profile so organizers and GOUP members can learn more about you.";

const profileIsIncomplete = (trigger) =>
  trigger?.closest?.("[data-profile-complete]")?.dataset.profileComplete === "false" ||
  document.querySelector("[data-logged-in='true'][data-profile-complete='false']") !== null;

export const showProfileCompletionFeedbackAlert = ({
  trigger,
  message,
  icon = "info",
  navigateTo = (url) => window.location.assign(url),
} = {}) => {
  if (!message || !profileIsIncomplete(trigger) || typeof globalThis.Swal?.fire !== "function") {
    return false;
  }

  Swal.fire({
    ...getCommonAlertOptions(),
    title: message,
    text: PROFILE_COMPLETION_MESSAGE,
    icon,
    confirmButtonText: "Complete profile",
    showCancelButton: true,
    cancelButtonText: "Maybe later",
  }).then((result) => {
    if (result.isConfirmed) {
      navigateTo(PROFILE_COMPLETION_URL);
    }
  });
  return true;
};

const promptAfterLogin = () => {
  if (sessionStorage.getItem("goup.profilePrompt") !== "true") return;
  sessionStorage.removeItem("goup.profilePrompt");
  if (!profileIsIncomplete()) return;
  showProfileCompletionFeedbackAlert({ message: "Complete your profile" });
};

const installLoginPrompt = (root = document) => {
  root.querySelectorAll('form[action^="/log-in"], a[href^="/log-in/oauth2/"], a[href^="/log-in/oidc/"]').forEach(
    (control) => control.addEventListener("click", () => sessionStorage.setItem("goup.profilePrompt", "true"), { once: true }),
  );
  promptAfterLogin();
};

initializeOnReadyAndHtmxLoad(installLoginPrompt);
