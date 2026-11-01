<script setup>
import ContactPanel from 'dashboard/routes/dashboard/conversation/ContactPanel.vue';

defineProps({
  currentChat: {
    required: true,
    type: Object,
  },
});
</script>

<template>
  <!-- No celular ocupa a tela toda e fecha pelo X do cabecalho. Sem fechar ao
  tocar fora: o unico "fora" seriam os modais e menus abertos pelo proprio
  painel, e toca-los desmontaria o painel junto com o modal. -->
  <div
    class="bg-n-surface-2 h-full overflow-hidden flex flex-col fixed top-0 z-40 w-full sm:max-w-sm transition-transform duration-300 ease-in-out ltr:right-0 rtl:left-0 md:static md:w-[320px] md:min-w-[320px] ltr:border-l rtl:border-r border-n-weak 2xl:min-w-[360px] 2xl:w-[360px] shadow-lg md:shadow-none"
  >
    <div class="flex flex-1 overflow-auto">
      <ContactPanel
        :conversation-id="currentChat.id"
        :inbox-id="currentChat.inbox_id"
      />
    </div>
  </div>
</template>
