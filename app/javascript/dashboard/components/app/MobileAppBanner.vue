<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Banner from 'dashboard/components/ui/Banner.vue';
import { useTouchDevice } from 'dashboard/composables/useTouchDevice';
import { useAppInstall } from 'dashboard/composables/useAppInstall';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { LocalStorage } from 'shared/helpers/localStorage';
import { requestPushPermissions } from 'dashboard/helper/pushHelper';

// So no celular, em duas etapas: instalar o app e depois ativar as
// notificacoes. No computador nada aparece; o pedido de push segue no perfil.
const { t } = useI18n();
const isTouchDevice = useTouchDevice();
const { canInstall, needsManualInstall, promptInstall } = useAppInstall();
const permission = ref('Notification' in window ? Notification.permission : '');
const dismissed = ref({
  install: !!LocalStorage.get(LOCAL_STORAGE_KEYS.DISMISSED_INSTALL_BANNER),
  push: !!LocalStorage.get(LOCAL_STORAGE_KEYS.DISMISSED_PUSH_BANNER),
});

const step = computed(() => {
  if (!isTouchDevice.value) return '';
  if (canInstall.value && !dismissed.value.install) return 'install';
  const canAskPermission =
    permission.value === 'default' && 'PushManager' in window;
  if (canAskPermission && !dismissed.value.push) return 'push';
  return '';
});

const bannerMessage = computed(() => {
  if (step.value === 'push') return t('APP_GLOBAL.PUSH_BANNER.MESSAGE');
  return needsManualInstall.value
    ? t('APP_GLOBAL.PUSH_BANNER.HOME_SCREEN')
    : t('APP_GLOBAL.INSTALL_APP.BANNER');
});

const onPrimaryAction = async () => {
  if (step.value === 'install') {
    promptInstall();
    return;
  }
  await requestPushPermissions({});
  permission.value = Notification.permission;
};

const dismissBanner = () => {
  const key =
    step.value === 'install'
      ? LOCAL_STORAGE_KEYS.DISMISSED_INSTALL_BANNER
      : LOCAL_STORAGE_KEYS.DISMISSED_PUSH_BANNER;
  LocalStorage.set(key, true);
  dismissed.value[step.value] = true;
};
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <Banner
    v-if="step"
    color-scheme="secondary"
    action-button-variant="solid"
    :banner-message="bannerMessage"
    :has-action-button="!(step === 'install' && needsManualInstall)"
    :action-button-label="
      step === 'install'
        ? t('APP_GLOBAL.INSTALL_APP.INSTALL')
        : t('APP_GLOBAL.PUSH_BANNER.ENABLE')
    "
    :action-button-icon="
      step === 'install' ? 'i-lucide-download' : 'i-lucide-bell'
    "
    has-close-button
    @primary-action="onPrimaryAction"
    @close="dismissBanner"
  />
</template>
