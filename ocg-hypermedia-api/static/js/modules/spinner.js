// Spinner

// Show spinner
export const showSpinner = () => {
  const content = document.getElementById('explore-content');
  content.classList.add('is-loading');
};

// Hide spinner
export const hideSpinner = () => {
  const content = document.getElementById('explore-content');
  content.classList.remove('is-loading');
};
