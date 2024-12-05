// Update results and results-mobile on DOM with content
export const updateResults = (content) => {
  const results = document.getElementById('results');
  results.innerHTML = content;
  const resultsMobile = document.getElementById('results-mobile');
  resultsMobile.innerHTML = content;
};

// Fetch API data for events or groups
export async function fetchData(entity, params) {
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

// Check if script is already loaded
export const checkIfScriptIsLoaded = (src) => {
  return Array.from(document.querySelectorAll('script')).map(scr => scr.src).includes(src);
};

// Show or hide mobile navbar
export const toggleNavbarMobile = () => {
  const navbarMobile = document.getElementById("navbar-mobile");
  navbarMobile.classList.toggle("hidden");
  const navbarBackdrop = document.getElementById("navbar-backdrop");
  navbarBackdrop.classList.toggle("hidden");
};

// Show or hide modal by id
export const updateModalStatus = (modalId) => {
  const modal = document.getElementById(modalId);
  if (modal.classList.contains("hidden")) {
    modal.classList.remove("hidden");
  } else {
    modal.classList.add("hidden");
  }
};

// Overwrite primary color in CSS
// (creo que esta función me la tengo que quedar yo)
export const overWritePrimaryColor = (color) => {
  const r = document.querySelector(':root');
  r.style.setProperty('--ocg-primary', color);
};
