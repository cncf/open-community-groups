/**
 * Opens the images carousel modal and sets the active image.
 * @param {string} modalId - The ID of the modal to open
 * @param {number} activeIndex - The index of the image to display
 */
export const openModal = (modalId, activeIndex) => {
  const modal = document.getElementById(modalId);
  if (modal) {
    setActiveImage(activeIndex - 1);

    modal.classList.remove("opacity-0");
    modal.classList.remove("pointer-events-none");
    modal.dataset.modal = "active";

    document.addEventListener("mousedown", closeModalOnBackgroundClick);
  }
};

/**
 * Closes the images carousel modal and removes event listeners.
 * @param {string} modalId - The ID of the modal to close
 */
export const closeModal = (modalId) => {
  const modal = document.getElementById(modalId);

  if (modal) {
    modal.classList.add("opacity-0");
    modal.classList.add("pointer-events-none");
    modal.dataset.modal = "";

    document.removeEventListener("mousedown", closeModalOnBackgroundClick);
  }
};

/**
 * Navigates the image carousel to the next or previous image.
 * @param {string} direction - The direction to navigate ('next' or 'prev')
 */
export const navigateCarousel = (direction) => {
  const carouselItems = document.querySelectorAll("#gallery [data-carousel-item]");

  if (carouselItems.length === 0) {
    let activeImageIndex = 0;
    carouselItems.forEach((item, index) => {
      if (item.dataset.carouselItem === "active") {
        activeImageIndex = index;
      }
    });

    // Update active item index based on direction
    if (direction === "next") {
      activeImageIndex++;

      // Reset to first item if last item is reached
      if (activeImageIndex >= carouselItems.length) {
        activeImageIndex = 0;
      }
    } else if (direction === "prev") {
      activeImageIndex--;

      // Reset to last item if first item is reached
      if (activeImageIndex < 0) {
        activeImageIndex = carouselItems.length - 1;
      }
    }

    setActiveImage(activeImageIndex);
  }
};

/**
 * Sets the active image in the carousel by updating CSS classes and data attributes.
 * @param {number} index - The index of the image to set as active
 */
const setActiveImage = (index) => {
  const carouselItems = document.querySelectorAll("#gallery [data-carousel-item]");
  if (carouselItems.length > 0) {
    carouselItems.forEach((item, i) => {
      if (i === index) {
        item.classList.remove("hidden");
        item.classList.remove("translate-x-full");
        item.classList.remove("z-10");
        item.classList.add("translate-x-0");
        item.classList.add("z-30");
        item.dataset.carouselItem = "active";
      } else {
        item.classList.add("hidden");
        item.classList.add("translate-x-full");
        item.classList.add("z-10");
        item.classList.remove("translate-x-0");
        item.classList.remove("z-30");
        item.dataset.carouselItem = "";
      }
    });
  }
};

/**
 * Closes the carousel modal when clicking on the background (not on buttons or images).
 * @param {Event} e - The mouse event object
 */
const closeModalOnBackgroundClick = (e) => {
  const activeModal = document.querySelector(".modal[data-modal='active']");
  if (activeModal) {
    if (e.target.parentElement.tagName !== "BUTTON" && !["IMG", "BUTTON"].includes(e.target.tagName)) {
      closeModal(activeModal.id);
    }
  }
};
