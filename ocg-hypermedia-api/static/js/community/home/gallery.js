// Gallery

// Open full modal with carousel of images by id
export const openFullModal = (modalId, activeIndex) => {
  const modal = document.getElementById(modalId);
  activateImageInCarousel(activeIndex - 1);

  modal.classList.remove("opacity-0");
  modal.classList.remove("pointer-events-none");
  modal.dataset.modal = "active";

  document.addEventListener("mousedown", onFullModalClick);
};

// Close full modal by id
export const closeFullModal = (modalId) => {
  const modal = document.getElementById(modalId);
  modal.classList.add("opacity-0");
  modal.classList.add("pointer-events-none");
  modal.dataset.modal = "";

  document.removeEventListener("mousedown", onFullModalClick);
};

// Close full modal on click outside
export const onFullModalClick = (e) => {
  const activeModal = document.querySelector(".modal[data-modal='active']");

  if (
    e.target.parentElement.tagName !== "BUTTON" &&
    !["IMG", "BUTTON"].includes(e.target.tagName)
  ) {
    closeFullModal(activeModal.id);
  }
};

// Activate image in carousel by index
export const activateImageInCarousel = (index) => {
  const carouselItems = document.querySelectorAll(
    "#gallery [data-carousel-item]"
  );
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

// Update active carousel item
export const updateActiveCarouselItem = (direction) => {
  const carouselItems = document.querySelectorAll(
    "#gallery [data-carousel-item]"
  );
  let activeItem = 0;
  carouselItems.forEach((item, index) => {
    if (item.dataset.carouselItem === "active") {
      activeItem = index;
    }
  });
  let activeItemIndex = activeItem;
  // Update active item index based on direction
  // Next item
  if (direction === "next") {
    activeItemIndex = activeItem + 1;
    // Reset to first item if last item is reached
    if (activeItemIndex >= carouselItems.length) {
      activeItemIndex = 0;
    }
    // Previous item
  } else if (direction === "prev") {
    activeItemIndex = activeItem - 1;
    // Reset to last item if first item is reached
    if (activeItemIndex < 0) {
      activeItemIndex = carouselItems.length - 1;
    }
  }

  // Activate image in carousel
  activateImageInCarousel(activeItemIndex);
};
