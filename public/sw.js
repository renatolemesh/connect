/* eslint-disable no-restricted-globals, no-console */
/* globals clients */

// Sem cache, nao ha o que preservar entre versoes: a nova assume na hora,
// inclusive nas janelas ja abertas, em vez de esperar todas fecharem.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', event => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('push', event => {
  let notification = event.data && event.data.json();

  event.waitUntil(
    self.registration.showNotification(notification.title, {
      body: notification.body,
      icon: '/brand-assets/app-icon-192.png',
      badge: '/brand-assets/notification-badge.png',
      // Uma notificacao por conversa: mensagem nova substitui a anterior e
      // toca de novo, como num app de mensagens.
      tag: notification.url,
      renotify: true,
      data: {
        url: notification.url,
      },
    })
  );
});

function openNotificationUrl(url) {
  // includeUncontrolled: a janela aberta antes do sw ativar tambem conta.
  return clients
    .matchAll({ type: 'window', includeUncontrolled: true })
    .then(windowClients => {
      let matchingWindowClient = windowClients.find(
        client => client.url === url
      );
      if (matchingWindowClient) {
        return matchingWindowClient.focus();
      }
      let [firstWindow] = windowClients;
      if (!firstWindow) {
        return clients.openWindow(url);
      }
      // App na tela: troca de conversa nele (App.vue escuta), sem recarregar.
      if (firstWindow.visibilityState === 'visible') {
        firstWindow.postMessage({ type: 'notification-click', url });
        return firstWindow.focus();
      }
      // Em segundo plano o celular congela ou recarrega a pagina ao voltar, e
      // a mensagem se perde: navega de verdade ate a conversa.
      return firstWindow
        .focus()
        .then(client => client.navigate(url))
        .catch(() => clients.openWindow(url));
    });
}

self.addEventListener('notificationclick', event => {
  event.notification.close();
  event.waitUntil(openNotificationUrl(event.notification.data.url));
});
