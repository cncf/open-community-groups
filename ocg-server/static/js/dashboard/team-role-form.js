import { closestElement, markDatasetReady } from "/static/js/common/dom.js";

const TEAM_ROLE_SELECT_SELECTOR = "[data-team-role-select]";

const initializeTeamRoleFormAutoSubmit = () => {
  if (!markDatasetReady(document.documentElement, "teamRoleFormAutoSubmitReady")) {
    return;
  }

  document.addEventListener("change", (event) => {
    const select = closestElement(event.target, TEAM_ROLE_SELECT_SELECTOR);
    if (select instanceof HTMLSelectElement) {
      select.form?.requestSubmit();
    }
  });
};

initializeTeamRoleFormAutoSubmit();
