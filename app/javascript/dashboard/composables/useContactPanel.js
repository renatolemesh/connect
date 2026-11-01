import { computed, ref } from 'vue';
import { useWindowSize } from '@vueuse/core';
import { useUISettings } from 'dashboard/composables/useUISettings';
import wootConstants from 'dashboard/constants/globals';

// No celular o painel do contato cobre a conversa inteira, entao o estado
// aberto/fechado fica so nesta aba. O is_contact_sidebar_open dos ui_settings
// e salvo na conta: quem deixa o painel aberto no computador abriria toda
// conversa no celular com o painel por cima, e fechar no celular fecharia
// tambem no computador.
const isOpenOnSmallScreen = ref(false);

export function useContactPanel() {
  const { uiSettings, updateUISettings } = useUISettings();
  const { width: windowWidth } = useWindowSize();

  const isSmallScreen = computed(
    () => windowWidth.value < wootConstants.SMALL_SCREEN_BREAKPOINT
  );

  const isContactPanelOpen = computed(() =>
    isSmallScreen.value
      ? isOpenOnSmallScreen.value
      : !!uiSettings.value.is_contact_sidebar_open
  );

  const setContactPanelOpen = isOpen => {
    if (isSmallScreen.value) {
      isOpenOnSmallScreen.value = isOpen;
      return;
    }
    updateUISettings({
      is_contact_sidebar_open: isOpen,
      is_copilot_panel_open: false,
    });
  };

  return {
    isSmallScreen,
    isContactPanelOpen,
    openContactPanel: () => setContactPanelOpen(true),
    closeContactPanel: () => setContactPanelOpen(false),
  };
}
