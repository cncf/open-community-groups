import { loadMap, toggleModalVisibility } from "/static/js/common/common.js";
import { getElementById, initializeOnReady, isDatasetReady, markDatasetReady } from "/static/js/common/dom.js";

const MAP_MODAL_SELECTOR = "[data-map-modal]";
const MAP_MODAL_READY_KEY = "mapModalReady";
const ENTER_KEY = "Enter";
const SPACE_KEY = " ";

/**
 * Reads a numeric coordinate from a map modal data attribute.
 * @param {HTMLElement} mapContainer - Map container element
 * @param {string} name - Dataset property name
 * @returns {number|null} Parsed coordinate when valid
 */
const readCoordinate = (mapContainer, name) => {
  const value = Number.parseFloat(mapContainer.dataset[name] || "");
  return Number.isNaN(value) ? null : value;
};

/**
 * Returns map modal roots inside the provided root, including the root itself.
 * @param {Document|Element} root - Root element containing map modal markers
 * @returns {HTMLElement[]} Map modal root elements
 */
const getMapModalRoots = (root) => {
  const roots = [];
  if (root instanceof HTMLElement && root.matches(MAP_MODAL_SELECTOR)) {
    roots.push(root);
  }
  roots.push(...root.querySelectorAll(MAP_MODAL_SELECTOR));
  return roots;
};

/**
 * Initializes one map modal from declarative data attributes.
 * @param {HTMLElement} mapContainer - Map preview container
 */
const initializeMapModal = (mapContainer) => {
  if (isDatasetReady(mapContainer, MAP_MODAL_READY_KEY)) {
    return;
  }

  const lat = readCoordinate(mapContainer, "lat");
  const lng = readCoordinate(mapContainer, "lng");
  const modalId = mapContainer.dataset.modalId;
  const modalMapId = mapContainer.dataset.modalMapId;
  if (lat === null || lng === null || !modalId || !modalMapId) {
    return;
  }

  markDatasetReady(mapContainer, MAP_MODAL_READY_KEY);
  let modalMapLoaded = false;

  const ensureModalMap = () => {
    if (modalMapLoaded) {
      return;
    }
    modalMapLoaded = true;
    requestAnimationFrame(() => {
      loadMap(modalMapId, lat, lng);
    });
  };

  const openModal = () => {
    toggleModalVisibility(modalId);
    ensureModalMap();
  };

  loadMap(mapContainer.id, lat, lng, { interactive: false });

  mapContainer.addEventListener("click", openModal);
  mapContainer.addEventListener("keydown", (event) => {
    if (event.key === ENTER_KEY || event.key === SPACE_KEY) {
      event.preventDefault();
      openModal();
    }
  });

  const closeButton = getElementById(document, mapContainer.dataset.closeButtonId || "");
  closeButton?.addEventListener("click", () => toggleModalVisibility(modalId));

  const backdrop = getElementById(document, mapContainer.dataset.backdropId || "");
  backdrop?.addEventListener("click", () => toggleModalVisibility(modalId));
};

/**
 * Initializes map modal widgets rendered by the server.
 * @param {Document|Element} root - Root element containing map modal markers
 */
export const initializeMapModals = (root = document) => {
  getMapModalRoots(root).forEach((mapContainer) => {
    initializeMapModal(mapContainer);
  });
};

initializeOnReady(() => initializeMapModals());
