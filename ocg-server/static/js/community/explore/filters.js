/**
 * Formats a date object to ISO format (YYYY-MM-DD).
 * @param {Date} date - The date object to format
 * @returns {string} The formatted date string in YYYY-MM-DD format
 */
const formatDate = (date) => {
  return date.toISOString().split("T")[0];
};

/**
 * Opens the filters drawer view (mobile only).
 * Removes CSS classes to show the drawer and backdrop.
 */
export const openFiltersDrawer = () => {
  const drawer = document.getElementById("drawer-filters");
  if (drawer) {
    drawer.classList.remove("-translate-x-full");
  }
  const backdrop = document.getElementById("drawer-backdrop");
  if (backdrop) {
    backdrop.classList.remove("hidden");
  }
};

/**
 * Closes the filters drawer view (mobile only).
 * Adds CSS classes to hide the drawer and backdrop.
 */
export const closeFiltersDrawer = () => {
  const drawer = document.getElementById("drawer-filters");
  if (drawer) {
    drawer.classList.add("-translate-x-full");
  }
  const backdrop = document.getElementById("drawer-backdrop");
  if (backdrop) {
    backdrop.classList.add("hidden");
  }
};

/**
 * Resets all filters in the specified form to their default values.
 * @param {string} formId - The ID of the form containing the filters to reset
 */
export const resetFilters = (formId) => {
  // Uncheck all checkboxes and radios
  document.querySelectorAll(`#${formId} input[type=checkbox]`).forEach((el) => (el.checked = false));
  document.querySelectorAll(`#${formId} input[type=radio]`).forEach((el) => (el.checked = false));

  // Date inputs are hidden when view mode is "calendar"
  const dateInputs = document.querySelectorAll(`#${formId} input[type=date]`);
  if (dateInputs.length > 0) {
    const { from, to } = getDefaultDateRange();
    // Reset date inputs
    dateInputs.forEach((el) => {
      if (el.name === "date_from") {
        el.value = from;
      } else if (el.name === "date_to") {
        el.value = to;
      }
    });
  } else {
    const { first, last } = getFirstAndLastDayOfMonth();

    const inputs = document.querySelectorAll(`#${formId} input[type=hidden]`);
    if (inputs) {
      inputs.forEach((input) => {
        if (input.name === "date_from") {
          input.value = first;
        } else if (input.name === "date_to") {
          input.value = last;
        }
      });
    }
  }

  // Reset text search input
  document.querySelector('input[name="ts_query"]').value = "";

  // Reset sort by
  const sortSelect = document.querySelector('select[name="sort_by"]');
  if (sortSelect) {
    sortSelect.value = "date";
  }

  // Select "Any" option when applicable
  document.querySelectorAll(`#${formId} input[value='']`).forEach((el) => (el.checked = true));

  // Trigger change event on the form to update results
  // This is necessary to ensure the filters are applied correctly
  // after resetting them.
  triggerChangeOnForm(formId);
};

/**
 * Resets date filters when in calendar view mode by clearing hidden date inputs.
 */
export const resetDateFiltersOnCalendarViewMode = () => {
  const inputs = document.querySelectorAll("input[type=hidden]");
  if (inputs.length === 0) {
    return;
  }

  inputs.forEach((input) => {
    if (input.name === "date_from" || input.name === "date_to") {
      input.value = "";
    }
  });
};

/**
 * Selects the "Any" option for a given filter, unchecking all other options.
 * @param {string} name - The name of the filter
 * @param {string} type - The type of filter
 * @param {boolean} triggerChange - Whether to trigger a form change event
 */
export const selectAnyOption = (name, type, triggerChange) => {
  const anyInput = document.getElementById(`any-${type}-${name}`);
  if (anyInput && !anyInput.isChecked) {
    // Uncheck all other options
    const inputs = document.querySelectorAll(`input[name='${name}']:checked`);
    inputs.forEach((input) => {
      input.checked = false;
    });

    // Check "Any" option
    anyInput.checked = true;

    // Trigger change on form if needed
    if (triggerChange) {
      const form = anyInput.closest("form");
      triggerChangeOnForm(form.id);
    }
  }
};

/**
 * Clears an input field and optionally triggers a form change event.
 * @param {string} id - The ID of the input field to clear
 * @param {string} formId - The ID of the form to trigger change on (optional)
 */
export const cleanInputField = (id, formId) => {
  const input = document.getElementById(id);
  input.value = "";

  if (formId) {
    triggerChangeOnForm(formId);
  }
};

/**
 * Triggers a change event on the specified form using htmx.
 * @param {string} formId - The ID of the form to trigger change on
 * @param {boolean} fromSearch - Whether the trigger comes from search input
 */
export const triggerChangeOnForm = (formId, fromSearch) => {
  // Prevent form submission if the search input is empty, and it is triggered
  // from the search input
  if (fromSearch) {
    const input = document.getElementById("ts_query");
    if (input && input.value === "") {
      return;
    }
  }

  const form = document.getElementById(formId);
  if (form) {
    // Trigger change event using htmx
    htmx.trigger(form, "change");
  }
};

/**
 * Handles search functionality when Enter key is pressed.
 * @param {KeyboardEvent} e - The keyboard event object
 * @param {string} formId - The ID of the form to submit (optional)
 */
export const searchOnEnter = (e, formId) => {
  if (e.key === "Enter") {
    if (formId) {
      triggerChangeOnForm(formId);
    } else {
      const value = e.currentTarget.value;
      if (value !== "") {
        document.location.href = `/explore?ts_query=${value}`;
      }
    }
    e.currentTarget.blur();
  }
};

/**
 * Expands collapsible filters that have active/checked options to ensure they are visible.
 */
export const expandFiltersUsed = () => {
  const collapsibles = document.querySelectorAll("[data-collapsible-item]");
  collapsibles.forEach((el) => {
    const filter = el.dataset.collapsibleLabel;
    const hiddenCheckedOptions = el.querySelectorAll("li.hidden input:checked");
    if (hiddenCheckedOptions.length > 0) {
      toggleCollapsibleFilterVisibility(filter);
    }
  });
};

/**
 * Toggles the visibility of a collapsible filter section.
 * @param {string} filter - The filter identifier to toggle
 */
export const toggleCollapsibleFilterVisibility = (filter) => {
  const collapsibles = document.querySelectorAll(`[data-collapsible-label='${filter}']`);
  collapsibles.forEach((collapsible) => {
    const maxItems = collapsible.dataset.maxItems;
    const isCollapsed = collapsible.classList.contains("collapsed");
    if (isCollapsed) {
      collapsible.classList.remove("collapsed");
      collapsible.querySelectorAll("li").forEach((el) => el.classList.remove("hidden"));
    } else {
      collapsible.classList.add("collapsed");
      collapsible.querySelectorAll("li[data-input-item]").forEach((el, index) => {
        // Hide all items after the max_visible_items_number (add 1 to include the "Any" option)
        if (index >= maxItems) {
          el.classList.add("hidden");
        }
      });
    }
  });
};

/**
 * Gets the first and last day of the month for the provided date.
 * @param {Date} date - The date to get the month boundaries for (defaults to current date)
 * @returns {object} Object with 'first' and 'last' properties containing formatted date strings
 */
export function getFirstAndLastDayOfMonth(date) {
  const currentDate = date || new Date();
  const lastDay = new Date(currentDate.getFullYear(), currentDate.getMonth() + 1, 0);

  const month = ("0" + (currentDate.getMonth() + 1)).slice(-2);
  const firstDayMonth = `${currentDate.getFullYear()}-${month}-01`;
  const lastDayMonth = `${currentDate.getFullYear()}-${month}-${lastDay.getDate()}`;

  return { first: firstDayMonth, last: lastDayMonth };
}

/**
 * Updates date input fields with the monthly range for the given date.
 * @param {Date} date - The date to use for calculating the monthly range
 */
export const updateDateInput = (date) => {
  const { first, last } = getFirstAndLastDayOfMonth(date);

  document.querySelectorAll("input[name=date_from]").forEach((el) => (el.value = first));
  document.querySelectorAll("input[name=date_to]").forEach((el) => (el.value = last));
};

/**
 * Gets the default date range from today to one year from now.
 * @returns {object} Object with 'from' and 'to' properties containing formatted date strings
 */
export const getDefaultDateRange = () => {
  const date = new Date();
  const aYearFromNow = new Date();
  aYearFromNow.setFullYear(aYearFromNow.getFullYear() + 1);

  return { from: formatDate(date), to: formatDate(aYearFromNow) };
};

/**
 * Unchecks all 'kind' filter options.
 */
export const unckeckAllKinds = () => {
  const kinds = document.querySelectorAll("input[name=kind]:checked");
  if (kinds) {
    kinds.forEach((el) => {
      el.checked = false;
    });
  }
};
