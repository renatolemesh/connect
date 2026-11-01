<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { useTouchDevice } from 'dashboard/composables/useTouchDevice';
import { useAppInstall } from 'dashboard/composables/useAppInstall';

// Lugar fixo para instalar, para quem fechou o aviso do topo. Some depois de
// instalado (o app abre sem barra do navegador).
const { t } = useI18n();
const isTouchDevice = useTouchDevice();
const { canInstall, needsManualInstall, promptInstall } = useAppInstall();
const stepsDialogRef = ref(null);

const install = () => {
  if (needsManualInstall.value) {
    stepsDialogRef.value.open();
    return;
  }
  promptInstall();
};
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <div v-if="isTouchDevice && canInstall" class="w-full px-1">
    <Button
      ghost
      slate
      sm
      icon="i-lucide-download"
      :label="t('APP_GLOBAL.INSTALL_APP.MENU')"
      class="w-full !justify-start"
      @click="install"
    />
    <Dialog
      ref="stepsDialogRef"
      :title="t('APP_GLOBAL.INSTALL_APP.IOS_TITLE')"
      :confirm-button-label="t('APP_GLOBAL.INSTALL_APP.IOS_CONFIRM')"
      :show-cancel-button="false"
      width="sm"
      @confirm="stepsDialogRef.close()"
    >
      <ol
        class="flex flex-col gap-2 mb-0 ps-5 text-sm list-decimal text-n-slate-12"
      >
        <li>{{ t('APP_GLOBAL.INSTALL_APP.IOS_STEP_SHARE') }}</li>
        <li>{{ t('APP_GLOBAL.INSTALL_APP.IOS_STEP_ADD') }}</li>
        <li>{{ t('APP_GLOBAL.INSTALL_APP.IOS_STEP_OPEN') }}</li>
      </ol>
    </Dialog>
  </div>
</template>
