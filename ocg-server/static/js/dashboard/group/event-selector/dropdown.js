import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { formatEventDate, getEventOptionState } from "/static/js/dashboard/group/event-selector/utils.js";

/**
 * Renders the compact event preview label.
 * @param {object} event Event payload.
 * @returns {import("lit").TemplateResult}
 */
export const renderEventSelectorPreview = (event) => {
  const formattedDate = formatEventDate(event);

  return html`
    <div class="flex flex-col min-w-0 pe-6 items-start">
      <div class="max-w-full truncate">${event.name ?? ""}</div>
      <div
        class="text-xs ${formattedDate.isPlaceholder ? "text-stone-400" : "text-stone-500"}
          truncate"
      >
        ${formattedDate.text}
      </div>
    </div>
  `;
};

/**
 * Renders an event selector option.
 * @param {Object} state Option state and callbacks.
 * @returns {import("lit").TemplateResult}
 */
export const renderEventSelectorOption = (state) => {
  const { isSelected, statusClass } = getEventOptionState({
    activeIndex: state.activeIndex,
    event: state.event,
    index: state.index,
    selectedEventId: state.selectedEventId,
  });

  return html`
    <li>
      <button
        id="select-event-${state.event.event_id}"
        type="button"
        class="event-button cursor-pointer w-full flex items-center justify-between px-4 py-2
          text-sm/6 text-left hover:bg-stone-100 ${statusClass}"
        ?disabled=${isSelected}
        @click=${(event) => state.onSelect(event, state.event)}
        @mouseenter=${() => state.onHighlight(state.index)}
      >
        ${renderEventSelectorPreview(state.event)}
      </button>
    </li>
  `;
};

/**
 * Renders dropdown content for the event selector.
 * @param {Object} state Dropdown state and callbacks.
 * @returns {import("lit").TemplateResult}
 */
export const renderEventSelectorDropdownContent = (state) => {
  if (state.error) {
    return html`<ul class="max-h-64 overflow-y-auto text-stone-700">
      <li class="px-4 py-4 text-sm text-stone-500">${state.error}</li>
    </ul>`;
  }

  if (!state.results || state.results.length === 0) {
    return html`<ul class="max-h-64 overflow-y-auto text-stone-700">
      <li class="px-4 py-4 text-sm text-stone-500">
        ${state.hasFetched ? "No events available." : "No events found."}
      </li>
    </ul>`;
  }

  return html`
    <ul class="max-h-64 overflow-y-auto text-stone-700">
      ${state.results.map((event, index) =>
        renderEventSelectorOption({
          activeIndex: state.activeIndex,
          event,
          index,
          onHighlight: state.onHighlight,
          onSelect: state.onSelect,
          selectedEventId: state.selectedEventId,
        }),
      )}
    </ul>
  `;
};
