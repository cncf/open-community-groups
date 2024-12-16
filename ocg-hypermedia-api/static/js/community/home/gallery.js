// Open images carousel modal.
export const openModal = (modalId, activeIndex) => {
  const modal = document.getElementById(modalId);
  setActiveImage(activeIndex - 1);

  modal.classList.remove("opacity-0");
  modal.classList.remove("pointer-events-none");
  modal.dataset.modal = "active";

  document.addEventListener("mousedown", closeModalOnBackgroundClick);
};

// Close images carousel modal.
export const closeModal = (modalId) => {
  const modal = document.getElementById(modalId);

  modal.classList.add("opacity-0");
  modal.classList.add("pointer-events-none");
  modal.dataset.modal = "";

  document.removeEventListener("mousedown", closeModalOnBackgroundClick);
};

// Navigate images carousel to next or previous image.
export const navigateCarousel = (direction) => {
  const carouselItems = document.querySelectorAll("#gallery [data-carousel-item]");

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
};

// Set active image in carousel.
const setActiveImage = (index) => {
  const carouselItems = document.querySelectorAll("#gallery [data-carousel-item]");
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
};

// Close images carousel modal on background click.
const closeModalOnBackgroundClick = (e) => {
  const activeModal = document.querySelector(".modal[data-modal='active']");

  if (e.target.parentElement.tagName !== "BUTTON" && !["IMG", "BUTTON"].includes(e.target.tagName)) {
    closeModal(activeModal.id);
  }
};
