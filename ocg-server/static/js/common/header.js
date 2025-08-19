/**
 * Toggles the user dropdown menu visibility and manages event listeners.
 * Handles click-outside-to-close functionality.
 */
export const onClickDropdown = () => {
  const dropdownButtonDesktop = document.getElementById("user-dropdown-button");
  const dropdownButtonMobile = document.getElementById("user-dropdown-button-mobile");
  const dropdownMenu = document.getElementById("dropdown-user");

  if (dropdownMenu) {
    const isHidden = dropdownMenu.classList.contains("hidden");

    if (isHidden) {
      dropdownMenu.classList.remove("hidden");

      const menuLinks = dropdownMenu.querySelectorAll("a");
      menuLinks.forEach((link) => {
        // Close dropdown when clicking on an action before loading the new page
        link.addEventListener("click", () => {
          const menu = document.getElementById("dropdown-user");
          if (menu) {
            menu.classList.add("hidden");
          }
        });
      });

      // Close dropdown when clicking outside
      const closeOnClickOutside = (event) => {
        const clickedOnDesktopButton = dropdownButtonDesktop && dropdownButtonDesktop.contains(event.target);
        const clickedOnMobileButton = dropdownButtonMobile && dropdownButtonMobile.contains(event.target);
        const clickedOnDropdown = dropdownMenu.contains(event.target);
        
        if (!clickedOnDropdown && !clickedOnDesktopButton && !clickedOnMobileButton) {
          dropdownMenu.classList.add("hidden");
          // Remove the event listener to prevent memory leaks
          document.removeEventListener("click", closeOnClickOutside);
        }
      };
      
      // Add the event listener with a small delay to prevent immediate closure
      setTimeout(() => {
        document.addEventListener("click", closeOnClickOutside);
      }, 10);
    } else {
      dropdownMenu.classList.add("hidden");
    }
  }
};