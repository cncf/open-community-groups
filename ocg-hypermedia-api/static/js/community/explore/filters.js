// Filters that are collapsible.
const COLLAPSIBLE_FILTERS = ["region", "distance"];

// Format date to ISO format (YYYY-MM-DD).
const formatDate = (date) => {
  return date.toISOString().split("T")[0];
};

// Open filters view (only for mobile).
export const open = () => {
  const drawer = document.getElementById("drawer-filters");
  drawer.classList.remove("-translate-x-full");
  const backdrop = document.getElementById("drawer-backdrop");
  backdrop.classList.remove("hidden");
};

// Close filters view (only for mobile).
export const close = () => {
  const drawer = document.getElementById("drawer-filters");
  drawer.classList.add("-translate-x-full");
  const backdrop = document.getElementById("drawer-backdrop");
  backdrop.classList.add("hidden");
};

// Reset all filters in the form provided.
export const reset = (formId) => {
  // Uncheck all checkboxes and radios
  document
    .querySelectorAll(`#${formId} input[type=checkbox]`)
    .forEach((el) => (el.checked = false));
  document
    .querySelectorAll(`#${formId} input[type=radio]`)
    .forEach((el) => (el.checked = false));

  // Reset date range
  document.querySelector("input[name=date_from]").value = formatDate(
    new Date()
  );
  const aYearFromNow = new Date();
  aYearFromNow.setFullYear(aYearFromNow.getFullYear() + 1);
  document.querySelector("input[name=date_to]").value =
    formatDate(aYearFromNow);
  document
    .querySelectorAll(`#${formId} input[type=date]`)
    .forEach((el) => (el.value = ""));

  // Reset text search input
  document.querySelector('input[name="ts_query"]').value = "";

  // Select "Any" option when applicable
  document
    .querySelectorAll(`#${formId} input[value='']`)
    .forEach((el) => (el.checked = true));

  triggerChangeOnForm(formId);
};

// Select "Any" option for the given filter name.
export const selectAnyOption = (name, triggerChange) => {
  const anyInput = document.getElementById(`any-${name}`);
  if (!anyInput.isChecked) {
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

// Clean input field and trigger change on form.
export const cleanInputField = (id, formId) => {
  const input = document.getElementById(id);
  input.value = "";

  if (formId) {
    triggerChangeOnForm(formId);
  } else {
    let form = input.closest("form");
    triggerChangeOnForm(form.id);
  }
};

// Trigger change on the form provided.
export const triggerChangeOnForm = (formId, fromSearch) => {
  // Prevent form submission if the search input is empty, and it is triggered
  // from the search input
  if (fromSearch) {
    const input = document.getElementById("ts_query");
    if (input.value === "") {
      return;
    }
  }

  const form = document.getElementById(formId);
  htmx.trigger(form, "change");
};

// Search on enter key press.
export const searchOnEnter = (e, formId) => {
  if (e.key === "Enter") {
    if (formId === "") {
      const value = e.currentTarget.value;
      if (value !== "") {
        document.location.href = `/explore?ts_query=${value}`;
      }
    } else {
      triggerChangeOnForm(formId);
    }
    e.currentTarget.blur();
  }
};

// Make sure that used filters are not hidden (collapsed).
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

// Toggle collapsible filter visibility.
export const toggleCollapsibleFilterVisibility = (filter) => {
  const collapsibles = document.querySelectorAll(
    `[data-collapsible-label='${filter}']`
  );
  collapsibles.forEach((collapsible) => {
    const maxItems = collapsible.dataset.maxItems;
    const isCollapsed = collapsible.classList.contains("collapsed");
    if (isCollapsed) {
      collapsible.classList.remove("collapsed");
      collapsible
        .querySelectorAll("li")
        .forEach((el) => el.classList.remove("hidden"));
    } else {
      collapsible.classList.add("collapsed");
      collapsible
        .querySelectorAll("li[data-input-item]")
        .forEach((el, index) => {
          // Hide all items after the max_visible_items_number (add 1 to include the "Any" option)
          if (index >= maxItems) {
            el.classList.add("hidden");
          }
        });
    }
  });
};
