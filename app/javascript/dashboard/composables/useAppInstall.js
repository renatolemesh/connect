import { ref, computed } from 'vue';
import { useMediaQuery } from '@vueuse/core';
import { isIOSDevice } from 'dashboard/helper/pushHelper';

// O Chrome oferece a instalacao uma vez, logo no carregamento: o evento fica
// guardado ate o toque em Instalar. Escuta no carregamento do modulo porque
// o evento pode chegar antes de qualquer componente montar.
const installPrompt = ref(null);
window.addEventListener('beforeinstallprompt', event => {
  event.preventDefault();
  installPrompt.value = event;
});
window.addEventListener('appinstalled', () => {
  installPrompt.value = null;
});

export function useAppInstall() {
  const isStandalone = useMediaQuery('(display-mode: standalone)');
  // iPhone nao tem como instalar por botao: so pelo Compartilhar do navegador.
  const needsManualInstall = computed(
    () => isIOSDevice() && !isStandalone.value
  );
  const canInstall = computed(
    () =>
      !isStandalone.value && (!!installPrompt.value || needsManualInstall.value)
  );

  const promptInstall = () => {
    // prompt() so pode ser chamado uma vez por evento.
    installPrompt.value?.prompt();
    installPrompt.value = null;
  };

  return { canInstall, needsManualInstall, promptInstall };
}
