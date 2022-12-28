import getAbsoluteURL, { isAbsoluteURL } from "discourse-common/lib/get-url";

export function registerServiceWorker(
  container,
  serviceWorkerURL,
  registerOptions = {}
) {
  if (window.isSecureContext && "serviceWorker" in navigator) {
    const caps = container.lookup("capabilities:main");
    const safariVersion = navigator.userAgent.match(/Version\/(\d+)/);
    const isOldSafari =
      caps.isSafari && safariVersion && parseInt(safariVersion[1], 10) < 16;

    if (serviceWorkerURL && !isOldSafari) {
      navigator.serviceWorker.getRegistrations().then((registrations) => {
        for (let registration of registrations) {
          if (
            registration.active &&
            !registration.active.scriptURL.includes(serviceWorkerURL)
          ) {
            unregister(registration);
          }
        }
      });

      navigator.serviceWorker
        .register(getAbsoluteURL(`/${serviceWorkerURL}`), registerOptions)
        .catch((error) => {
          // eslint-disable-next-line no-console
          console.info(`Failed to register Service Worker: ${error}`);
        });
    } else {
      navigator.serviceWorker.getRegistrations().then((registrations) => {
        for (let registration of registrations) {
          unregister(registration);
        }
      });
    }
  }
}

function unregister(registration) {
  if (isAbsoluteURL(registration.scope)) {
    registration.unregister();
  }
}
