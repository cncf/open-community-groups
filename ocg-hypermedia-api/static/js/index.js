const COLLAPSIBLE_FILTERS = ['region', 'distance'];

const toggleNavbarMobile = () => {
  const navbarMobile = document.getElementById("navbar-mobile");
  navbarMobile.classList.toggle("hidden");
  const navbarBackdrop = document.getElementById("navbar-backdrop");
  navbarBackdrop.classList.toggle("hidden");
};

const updateModalStatus = (modalId) => {
  const modal = document.getElementById(modalId);
  if (modal.classList.contains("hidden")) {
    modal.classList.remove("hidden");
  } else {
    modal.classList.add("hidden");
  }
};

const formatDate = (date) => {
  date.toISOString().split('T')[0]
}

// Filters
const openFilters = () => {
  const drawer = document.getElementById("drawer-filters");
  drawer.classList.remove("-translate-x-full");
  const backdrop = document.getElementById("drawer-backdrop");
  backdrop.classList.remove("hidden");
};

const closeFilters = () => {
  const drawer = document.getElementById("drawer-filters");
  drawer.classList.add("-translate-x-full");
  const backdrop = document.getElementById("drawer-backdrop");
  backdrop.classList.add("hidden");
};

const resetFilters = (formName) => {
  const form = document.getElementById(formName);
  document.querySelectorAll(`#${formName} input[type=checkbox]`).forEach(el => el.checked = false);
  document.querySelectorAll(`#${formName} input[type=radio]`).forEach(el => el.checked = false);
  document.querySelectorAll(`#${formName} input[value='']`).forEach(el => el.checked = true);
  document.querySelector('input[name=date_from]').value = formatDate(new Date());
  const aYearFromNow = new Date();
  aYearFromNow.setFullYear(aYearFromNow.getFullYear() + 1);
  document.querySelector('input[name=date_to]').value = formatDate(aYearFromNow);
  document.querySelectorAll(`#${formName} input[type=date]`).forEach(el => el.value = '');
  document.querySelector('input[name="ts_query"]').value = '';

  triggerChangeOnForm(form.id);
};

const updateAnyValue = (name, triggerChange) => {
  const anyInput = document.getElementById(`any-${name}`);
  if (!anyInput.isChecked) {
    const inputs = document.querySelectorAll(`input[name='${name}']:checked`);
    inputs.forEach((input) => {
      input.checked = false;
    });
    anyInput.checked = true;
    if (triggerChange) {
      const form = anyInput.closest('form');
      triggerChangeOnForm(form.id);
    }
  }
};

const cleanInputField = (id, formId) => {
  const input = document.getElementById(id);
  input.value = '';

  if (formId) {
    triggerChangeOnForm(formId);
  } else {
    let form = input.closest('form');
    triggerChangeOnForm(form.id);
  }
};

const triggerChangeOnForm = (formId, fromSearchSearch) => {
  if (fromSearchSearch) {
    const input = document.getElementById('ts_query');
    // Prevent form submission if the search input is empty
    if (input.value === '') {
      return;
    }
  }
  const form = document.getElementById(formId);
  htmx.trigger(form, "change");
};

const loadExplorePageWithTsQuery = () => {
  const input = document.getElementById('ts_query');
  if (input.value !== '') {
    document.location.href = `/explore?ts_query=${input.value}`;
  }
};

const onSearchKeyDown = (e, formId) => {
  if (e.key === 'Enter') {
    if (formId === '') {
      const value = e.currentTarget.value;
      if (value !== '') {
        document.location.href = `/explore?ts_query=${value}`;
      }
    } else {
      triggerChangeOnForm(formId);
    }
    e.currentTarget.blur();
  }
};

const checkVisibleFilters = () => {
  const collapsibleItems = document.querySelectorAll('[data-collapsible-item]');
  collapsibleItems.forEach(item => {
    const filter = item.id.replace('collapsible-', '');
    const hiddenCheckedOptions = item.querySelectorAll('li.hidden input:checked');
    if (hiddenCheckedOptions.length > 0) {
      updateCollapsibleFilterStatus(`collapsible-${filter}`);
    }
  });
};

// Spinner
const showSpinner = () => {
  const content = document.getElementById('explore-content');
  content.classList.add('is-loading');
};

const hideSpinner = () => {
  const content = document.getElementById('explore-content');
  content.classList.remove('is-loading');
};

// Collapsible filter
const updateCollapsibleFilterStatus = (id) => {
  const filter = document.getElementById(id);
  const maxItems = filter.dataset.maxItems;
  const isCollapsed = filter.classList.contains('collapsed');
  if (isCollapsed) {
    filter.classList.remove('collapsed');
    filter.querySelectorAll('li').forEach(el => el.classList.remove('hidden'));
  } else {
    filter.classList.add('collapsed');
    filter.querySelectorAll('li[data-input-item]').forEach((el, index) => {
      // Hide all items after the max_visible_items_number (add 1 to include the "Any" option)
      if (index >= maxItems) {
        el.classList.add('hidden');
      }
    });
  }
}

// Explore - results
const updateResults = (content) => {
  const results = document.getElementById('results');
  results.innerHTML = content;
  const resultsMobile = document.getElementById('results-mobile');
  resultsMobile.innerHTML = content;
};

// Gallery
const openFullModal = (modalId, activeIndex) => {
  const modal = document.getElementById(modalId);
  activateImageInCarousel(activeIndex - 1);

  modal.classList.remove('opacity-0');
  modal.classList.remove('pointer-events-none');
  modal.dataset.modal = 'active';

  document.addEventListener('mousedown', onFullModalClick);
};

const closeFullModal = (modalId) => {
  const modal = document.getElementById(modalId);
  modal.classList.add('opacity-0');
  modal.classList.add('pointer-events-none');
  modal.dataset.modal = '';

  document.removeEventListener('mousedown', onFullModalClick);
};

const onFullModalClick = (e) => {
  const activeModal = document.querySelector(".modal[data-modal='active']");

  if (e.target.parentElement.tagName !== 'BUTTON' && !['IMG', 'BUTTON'].includes(e.target.tagName)) {
    closeFullModal(activeModal.id);
  }
};

const activateImageInCarousel = (index) => {
  const carouselItems = document.querySelectorAll('#gallery [data-carousel-item]');
  carouselItems.forEach((item, i) => {
    if (i === index) {
      item.classList.remove('hidden');
      item.classList.remove('translate-x-full');
      item.classList.remove('z-10');
      item.classList.add('translate-x-0');
      item.classList.add('z-30');
      item.dataset.carouselItem = 'active';
    } else {
      item.classList.add('hidden');
      item.classList.add('translate-x-full');
      item.classList.add('z-10');
      item.classList.remove('translate-x-0');
      item.classList.remove('z-30');
      item.dataset.carouselItem = '';
    }
  });
};

const updateActiveCarouselItem = (direction) => {
  const carouselItems = document.querySelectorAll('#gallery [data-carousel-item]');
  let activeItem = 0;
  carouselItems.forEach((item, index) => {
    if (item.dataset.carouselItem === 'active') {
      activeItem = index;
    }
  });
  let activeItemIndex = activeItem;
  if (direction === 'next') {
    activeItemIndex = activeItem + 1;
    if (activeItemIndex >= carouselItems.length) {
      activeItemIndex = 0;
    }
  } else if (direction === 'prev') {
    activeItemIndex = activeItem - 1;
    if (activeItemIndex < 0) {
      activeItemIndex = carouselItems.length - 1;
    }
  }

  activateImageInCarousel(activeItemIndex);
};

const hashCode = (str) => {
  let hash = 0;
  if (str.length === 0) return hash;
  for (let i = 0; i < str.length; i++) {
    const chr = str.charCodeAt(i);
    hash = ((hash << 5) - hash) + chr;
    hash |= 0; // Convert to 32bit integer
  }
  return Math.abs(hash);
}

const getBackgroundColor = (name) => {
  const hash = hashCode(name);
  return img_colors[hash % img_colors.length];
}

const fillEmptyImages = () => {
  const emptyLogos = document.querySelectorAll('[data-placeholder-logo]');
  emptyLogos.forEach((image) => {
    const name = image.dataset.placeholderName;
    image.style.backgroundColor = getBackgroundColor(name);
  });
};

const checkIfScriptIsLoaded = (src) => {
  return Array.from(document.querySelectorAll('script')).map(scr => scr.src).includes(src);
};

const getRandomInteger = (min, max) => {
  min = Math.ceil(min)
  max = Math.floor(max)

  return Math.floor(Math.random() * (max - min)) + min
}

const getMiniEvent = (event, titleClass) => {
  return `
  <div class="max-w-full">
    <div class="font-semibold text-xs mb-2 line-clamp-3 ${titleClass}">${event.name}</div>
    <div class="flex flex-1 flex-row items-stretch">
      ${event.logo_url ? ` <div
        class="h-14 w-14 min-w-14 my-auto bg-no-repeat bg-center bg-cover rounded-lg border"
        style="background-image: url(${event.logo_url.replace('c_fill,dpr_2,f_auto,g_center,q_auto:good', 'c_scale,w_112')});"
      ></div>`: `<div
        class="relative md:my-auto bg-white rounded-lg outline outline-1 outline-gray-300 border border-[5px] border-white overflow-hidden bg-no-repeat bg-center bg-contain h-14 w-14 min-w-14"
      ><div class="absolute w-full h-full top-0" style="mask-image: url(/static/images/placeholder_cncf.png);mask-mode: alpha;mask-size: cover; background-color: ${getBackgroundColor(event.name)};"></div></div>`}


      <div class="min-w-0 pl-3 content-center">
        <div class="flex flex-col justify-between w-full h-full">
          <div>
            <div class="truncate text-gray-400 leading-3">
              <span class="text-[0.65rem] font-semibold tracking-wide uppercase">${event.group_name}</span>
            </div>
          </div>

          <div>
            ${event.kind_id === 'virtual' ? `<div class="flex flex-row items-center leading-4 pt-1">
                <svg class="-mt-[2px] w-3 h-3 me-1" stroke="currentColor" fill="currentColor" stroke-width="0" viewBox="0 0 384 512" height="1em" width="1em" xmlns="http://www.w3.org/2000/svg"><path d="M215.7 499.2C267 435 384 279.4 384 192C384 86 298 0 192 0S0 86 0 192c0 87.4 117 243 168.3 307.2c12.3 15.3 35.1 15.3 47.4 0zM192 128a64 64 0 1 1 0 128 64 64 0 1 1 0-128z"></path></svg>
                <div class="truncate text-gray-700 text-[0.65rem] uppercase">Virtual</div>
              </div>` : `${event.venue_city ? `
              <div class="flex flex-row items-center leading-4 pt-1">
                <svg class="-mt-[2px] w-3 h-3 me-1" stroke="currentColor" fill="currentColor" stroke-width="0" viewBox="0 0 384 512" height="1em" width="1em" xmlns="http://www.w3.org/2000/svg"><path d="M215.7 499.2C267 435 384 279.4 384 192C384 86 298 0 192 0S0 86 0 192c0 87.4 117 243 168.3 307.2c12.3 15.3 35.1 15.3 47.4 0zM192 128a64 64 0 1 1 0 128 64 64 0 1 1 0-128z"></path></svg>
                <div class="truncate text-gray-700 text-[0.65rem] uppercase">
                  ${event.venue_city}${event.group_state ? `, ${event.group_state}` : ''}
                </div>
              </div>
            ` : ''}`}

            <div class="flex flex-row items-center">
              <svg class="-mt-[2px] w-3 h-3 me-1" stroke="currentColor" fill="currentColor" stroke-width="0" viewBox="0 0 448 512" height="1em" width="1em" xmlns="http://www.w3.org/2000/svg"><path d="M128 0c13.3 0 24 10.7 24 24V64H296V24c0-13.3 10.7-24 24-24s24 10.7 24 24V64h40c35.3 0 64 28.7 64 64v16 48V448c0 35.3-28.7 64-64 64H64c-35.3 0-64-28.7-64-64V192 144 128C0 92.7 28.7 64 64 64h40V24c0-13.3 10.7-24 24-24zM400 192H48V448c0 8.8 7.2 16 16 16H384c8.8 0 16-7.2 16-16V192zM329 297L217 409c-9.4 9.4-24.6 9.4-33.9 0l-64-64c-9.4-9.4-9.4-24.6 0-33.9s24.6-9.4 33.9 0l47 47 95-95c9.4-9.4 24.6-9.4 33.9 0s9.4 24.6 0 33.9z"></path></svg>
              <span class="text-gray-700 text-[0.65rem] uppercase truncate">${new Date(event.starts_at * 1000).toLocaleDateString()}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>`;
};

const getMiniGroup = (group, titleClass) => {
  return `
  <div>
    <div class="font-semibold text-xs mb-2 line-clamp-3 ${titleClass}">${group.name}</div>
    <div class="flex flex-1 flex-row items-stretch">
      ${group.logo_url ? ` <div
        class="h-14 w-14 min-w-14 my-auto bg-no-repeat bg-center bg-cover rounded-lg border"
        style="background-image: url(${group.logo_url.replace('c_fill,dpr_2,f_auto,g_center,q_auto:good', 'c_scale,w_112')});"
      ></div>`: `<div
        class="relative md:my-auto bg-white rounded-lg outline outline-1 outline-gray-300 border border-[5px] border-white overflow-hidden bg-no-repeat bg-center bg-contain h-14 w-14 min-w-14"
      ><div class="absolute w-full h-full top-0" style="mask-image: url(/static/images/placeholder_cncf.png);mask-mode: alpha;mask-size: cover; background-color: ${getBackgroundColor(group.name)};"></div></div>`}

      <div class="min-w-0 pl-3 content-center">
        <div class="flex flex-col justify-between w-full h-full">
          <div>
            <div class="truncate text-gray-400 leading-3">
              <span class="text-[0.65rem] font-semibold tracking-wide uppercase">${group.region_name || group.category_name}</span>
            </div>
          </div>

          <div>
            <div class="flex flex-row items-center leading-4 pt-1">
              <svg class="-mt-[2px] w-3 h-3 me-1" stroke="currentColor" fill="currentColor" stroke-width="0" viewBox="0 0 384 512" height="1em" width="1em" xmlns="http://www.w3.org/2000/svg"><path d="M215.7 499.2C267 435 384 279.4 384 192C384 86 298 0 192 0S0 86 0 192c0 87.4 117 243 168.3 307.2c12.3 15.3 35.1 15.3 47.4 0zM192 128a64 64 0 1 1 0 128 64 64 0 1 1 0-128z"></path></svg>
              <div class="truncate text-gray-700 text-[0.65rem] uppercase">
                ${group.city ? `${group.city}${group.country ? `, ${group.country}` : ''}` : ''}
              </div>
            </div>

            <div class="flex flex-row items-center">
              <svg class="-mt-[2px] w-3 h-3 me-1" stroke="currentColor" fill="currentColor" stroke-width="0" viewBox="0 0 448 512" height="1em" width="1em" xmlns="http://www.w3.org/2000/svg"><path d="M128 0c13.3 0 24 10.7 24 24V64H296V24c0-13.3 10.7-24 24-24s24 10.7 24 24V64h40c35.3 0 64 28.7 64 64v16 48V448c0 35.3-28.7 64-64 64H64c-35.3 0-64-28.7-64-64V192 144 128C0 92.7 28.7 64 64 64h40V24c0-13.3 10.7-24 24-24zM400 192H48V448c0 8.8 7.2 16 16 16H384c8.8 0 16-7.2 16-16V192zM329 297L217 409c-9.4 9.4-24.6 9.4-33.9 0l-64-64c-9.4-9.4-9.4-24.6 0-33.9s24.6-9.4 33.9 0l47 47 95-95c9.4-9.4 24.6-9.4 33.9 0s9.4 24.6 0 33.9z"></path></svg>
              <span class="text-gray-700 text-[0.65rem] uppercase truncate">${new Date(group.created_at * 1000).toLocaleDateString()}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>`;
};

/* ***
  * Calendar *
* *** */

let calendar = null;

const updateCalendarDate = () => {
  if (calendar) {
    const el = document.getElementById('calendar-date');
    if (el) {
      el.textContent = calendar.currentData.viewTitle;
    }
  }
}

async function fetchData(entity, params) {
  const url = `/explore/${entity}/search?${params}`;
  try {
    const response = await fetch(url);
    if (!response.ok) {
      throw new Error(`Response status: ${response.status}`);
    }

    const json = await response.json();
    return json;
  } catch (error) {
    // TODO - Handle error
    console.error(error.message);
  }
}

const loadCalendar = (entity) => {
  const createTooltip = (id, event, horizontalAlignment, verticalAlignment) => {
    const tooltip = `<div id="${id}" role="tooltip" data-popover="true" class="absolute ${horizontalAlignment == 'right' ? 'end-0' : ''} ${verticalAlignment == 'top' ? 'top-0 -translate-y-full' : ''} z-10 invisible inline-block w-64 text-sm text-gray-500 transition-opacity duration-300 bg-white border border-gray-200 rounded-lg shadow-sm opacity-0 p-2">
      ${getMiniEvent(event)}
    </div>`;

    return tooltip;
  }

  const renderCalendar = () => {
    const calendarEl = document.getElementById('calendar-box');

    if (calendar) {
      calendar.destroy();
    }

    // Initialize calendar
    calendar = new FullCalendar.Calendar(calendarEl, {
      timeZone: 'local',
      initialView: 'dayGridMonth',
      displayEventTime: false,
      eventDisplay: 'block',
      events: [],
      selectable: false,
      showNonCurrentDates: false,
      headerToolbar: false,
      dayMaxEventRows: 4,
      moreLinkClick: 'popover',
      eventClick: (info) => {
        console.log('Event: ' + info.event.name + info.view.type);
      },
      eventDidMount: (info) => {
        // Calculate alignment based on the position of the event in the calendar
        const horizontalAlignment = info.el.fcSeg.firstCol > 4 ? 'right' : 'left';
        const verticalAlignment = info.el.fcSeg.row > 4 ? 'top' : 'bottom';

        // Add tooltip
        const id = `popover-${info.event.extendedProps.event.slug}`;
        info.el.parentNode.setAttribute('popovertarget', id);
        info.el.parentNode.insertAdjacentHTML('beforeend', createTooltip(id, info.event.extendedProps.event, horizontalAlignment, verticalAlignment));
      },
    });

    updateCalendarDate();
    loadNewEvents(entity);
    calendar.render();
  };

  // If fullcalendar script is not loaded, load it
  if (!checkIfScriptIsLoaded('fullcalendar')) {
    let script = document.createElement('script');
    script.type = 'text/javascript';
    // Load only required libraries
    script.src = 'https://cdn.jsdelivr.net/npm/fullcalendar@6.1.15/index.global.min.js';
    document.getElementsByTagName('head')[0].appendChild(script);
    script.onload = () => {
      renderCalendar();
    };
  } else {
    loadNewEvents(entity);
  }
};

const loadNewEvents = async (entity) => {
  // Colors for category group
  const COLORS = ["#219EBC", "#C32F27", "#3B7346", "#FB8500", "#023047"];

  const convertDate = (date) => {
    return date.toISOString();
  }

  let date = new Date();
  if (calendar) {
    date = calendar.getDate();
  }
  const firstDayMonth = new Date(date.getFullYear(), date.getMonth(), 1);
  const lastDayMonth = new Date(date.getFullYear(), date.getMonth() + 1, 0);

  const params = new URLSearchParams(location.search);
  params.delete('view_mode');
  params.delete('date_from');
  params.delete('data_to');

  // Update date range on form?
  params.append('date_from', firstDayMonth.toISOString());
  params.append('date_to', lastDayMonth.toISOString());

  params.append('limit', 100);
  params.append('offset', 0);

  const data = await fetchData(entity, params.toString());

  if (data.events && data.events.length > 0) {
    let formattedEvents = data.events.map(event => {
      // Badge color for past events
      let color = 'rgb(175, 175, 175)';
      if (!event.starts_at) {
        return;
      }

      // Get end date
      const endDate = event.ends_at ? new Date(event.ends_at * 1000) : new Date(event.starts_at * 1000);

      // Set end date to the end of the day to get badge color
      const endDateNoTime = endDate;
      endDateNoTime.setHours(23);
      endDateNoTime.setMinutes(59);
      endDateNoTime.setSeconds(59);

      console.log('event -z', event.name, event.starts_at, event.ends_at)

      // Get background color badge for future events
      const diff = new Date().getTime() - endDateNoTime.getTime();
      if (diff < 0) {
        const hash = hashCode(event.group_name);
        color = COLORS[hash % COLORS.length];
      }

      // Add event to calendar
      return {
        title: event.name,
        // allDay: true,
        start: convertDate(new Date(event.starts_at * 1000)),
        end: convertDate(endDate),
        className: `cursor-pointer ${event.kind_id}`,
        backgroundColor: color,
        borderColor: color,
        extendedProps: {
          event: event,
        },
      };
    });

    calendar.removeAllEvents();
    calendar.addEventSource(formattedEvents);
  }
}

// Load current month data
const loadCurrentMonth = (entity) => {
  if (calendar) {
    calendar.today();
    updateCalendarDate();
    loadNewEvents(entity);
  }
}

// Load next month data
const loadNextMonth = (entity) => {
  if (calendar) {
    calendar.next();
    updateCalendarDate();
    loadNewEvents(entity);
  }
}

// Load previous month data
const loadPrevMonth = (entity) => {
  if (calendar) {
    calendar.prev();
    updateCalendarDate();
    loadNewEvents(entity);
  }
}
/* ***
  * End calendar *
* *** */

/* ***
  * Map *
* *** */
let map = null;

const loadMap = (entity) => {
  const renderMap = () => {
    if (map) {
      map.remove();
    }

    map = L.map('map-box', {
      maxZoom: 20,
      minZoom: 3,
      zoomControl: false,
    });
    const layerGroup = L.layerGroup();

    L.control.zoom({
      position: 'topright'
    }).addTo(map);

    const loadMapData = async (currentMap, overwriteBounds) => {
      const bounds = currentMap.getBounds();

      const params = new URLSearchParams(location.search);
      params.delete('view_mode');
      params.append('limit', 100);
      params.append('offset', 0);
      params.append('kind', 'in-person');
      params.append('kind', 'hybrid');

      if (overwriteBounds) {
        params.append('include_bbox', true);
      } else {
        params.append('bbox_sw_lat', bounds._southWest.lat);
        params.append('bbox_sw_lon', bounds._southWest.lng);
        params.append('bbox_ne_lat', bounds._northEast.lat);
        params.append('bbox_ne_lon', bounds._northEast.lng);
      }

      const data = await fetchData(entity, params.toString());
      if (data) {
        if (overwriteBounds && data.bbox) {
          const southWest = L.latLng(data.bbox.sw_lat, data.bbox.sw_lon);
          const northEast = L.latLng(data.bbox.ne_lat, data.bbox.ne_lon);
          const bounds = L.latLngBounds(southWest, northEast);
          currentMap.fitBounds(bounds);
        }

        const svgIcon = {
          html: '<svg stroke="currentColor" fill="currentColor" stroke-width="0" viewBox="0 0 20 20" aria-hidden="true" xmlns="http://www.w3.org/2000/svg"><path fill-rule="evenodd" d="M5.05 4.05a7 7 0 119.9 9.9L10 18.9l-4.95-4.95a7 7 0 010-9.9zM10 11a2 2 0 100-4 2 2 0 000 4z" clip-rule="evenodd"></path></svg>',
          iconSize: [30, 30],
          iconAnchor: [15, 30],
          popupAnchor: [0, -25]
        };

        let newItems = [];

        if (entity === 'events') {
          if (data.events && data.events.length > 0) {
            newItems = data.events;
          }
        } else if (entity === 'groups') {
          if (data.groups && data.groups.length > 0) {
            newItems = data.groups;
          }
        }

        if (newItems.length > 0) {
          const mapList = document.getElementById('map-content');
          mapList.innerHTML = '';

          // Clear previous markers
          if (currentMap.hasLayer(layerGroup)) {
            layerGroup.clearLayers();
          }

          newItems.forEach((item) => {
            if (item.latitude == 0 || item.longitude == 0) {
              return;
            }

            const icon = L.divIcon({...svgIcon, className: `text-primary-500 marker-${item.slug}`});
            const marker = L.marker(L.latLng(item.latitude, item.longitude), { icon: icon, bubblingMouseEvents: true });

            const elContent = entity == 'events' ? getMiniEvent(item, 'pe-3') : getMiniGroup(item, 'pe-3');
            const itemEl = `<div id="${item.slug}_${item.slug}" class="flex flex-1 flex-row items-center bg-white/90 backdrop-blur-sm p-2 border rounded-lg m-1.5 cursor-pointer hover:bg-gray-50/90" onmouseenter="hoverMapItem('${item.slug }')" onmouseleave="outMapItem('${item.slug}')">${elContent}</div>`;
            mapList.insertAdjacentHTML('afterbegin', itemEl);

            marker.bindPopup(`<div class="flex flex-1 flex-row items-center min-w-[210px] max-w-[210px] md:max-w-[240px] lg:max-w-[275px]">${elContent}</div>`);

            layerGroup.addLayer(marker);
            currentMap.addLayer(layerGroup);
          });
        }
      }
    }

    // Load events after the map is loaded
    map.on('load', () => {
      loadMapData(map, true);
    });

    // Setting the position of the map: lat/long and zoom level
    map.setView([36.7650, -4.4239], 9);

    // Fix center visible area for desktop
    // TODO mobile
    map.panBy([-(map.getSize().x / 4), 0], { animate: false });

    L.tileLayer(`https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}${L.Browser.retina ? '@2x.png' : '.png'}`, {
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>',
      subdomains: 'abcd',
      maxZoom: 20,
      minZoom: 0
    }).addTo(map);

    // Adding a listener to the map after setting the position to get the bounds
    // when the map is moved (zoom or pan)
    map.on('moveend', () => {
      loadMapData(map);
    });
  };

  if (!checkIfScriptIsLoaded('leaflet')) {
    let script = document.createElement('script');
    script.type = 'text/javascript';
    script.src = 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.js';
    document.getElementsByTagName('head')[0].appendChild(script);
    script.onload = () => {
      renderMap();
    };
  } else {
    renderMap();
  }
}

const hoverMapItem = (id) => {
  const marker = document.querySelector(`.marker-${id}`);
  if (marker) {
    marker.classList.add('text-primary-900');
  }
};

const outMapItem = (id) => {
    const marker = document.querySelector(`.marker-${id}`);
    if (marker) {
      marker.classList.remove('text-primary-900');
    }
  };
// End map

// Colors
const hexToRGB = (hexColor) => {
  let color = hexColor.replace("#", "");
  if (color.length === 3) {
    color = color
      .split("")
      .map((char) => char + char)
      .join("");
  }

  const r = parseInt(color.slice(0, 2), 16);
  const g = parseInt(color.slice(2, 4), 16);
  const b = parseInt(color.slice(4, 6), 16);

  return {r: r, g: g, b: b};
};

const rgbToHex = (r, g, b) => {
  return `#${[r, g, b]
    .map(x => x.toString(16).padStart(2, '0'))
    .join('')}`;
};

const overWritePrimaryColor = (color) => {
  const r = document.querySelector(':root');
  r.style.setProperty('--ocg-primary', color);
};

const calculatePalette = (hexColor) => {
  const {r, g, b} = {...hexToRGB(hexColor)};

  const getTint = (percentage) => {
    const tintR = Math.round(Math.min(255, r + (255 - r) * percentage));
    const tintG = Math.round(Math.min(255, g + (255 - g) * percentage));
    const tintB = Math.round(Math.min(255, b + (255 - b) * percentage));

    return rgbToHex(tintR, tintG, tintB);
  }

  const getShade = (percentage) => {
    const shadeR = Math.round(Math.max(0, r - r * percentage));
    const shadeG = Math.round(Math.max(0, g - g * percentage));
    const shadeB = Math.round(Math.max(0, b - b * percentage));

    return rgbToHex(shadeR, shadeG, shadeB);
  };

  return {
    50: getTint(0.95),
    100: getTint(0.9),
    300: getTint(0.5),
    500: hexColor,
    700: getShade(0.2),
    900: getShade(0.5),
  };
};

let placeholder_colors = ["#fa4a18", "#f1c232", "#6aa84f", "#3d85c6"];

// Prepare colors for empty event images
let img_colors = [];
placeholder_colors.forEach(color => {
  const {r, g, b} = {...hexToRGB(color)};
  img_colors.push(`rgba(${r}, ${g}, ${b}, 0.3)`);
});
