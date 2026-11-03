<script>
import { useAlert } from 'dashboard/composables';
import EmojiOrIcon from 'shared/components/EmojiOrIcon.vue';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import NextButton from 'dashboard/components-next/button/Button.vue';
import InlineInput from 'dashboard/components-next/inline-input/InlineInput.vue';

export default {
  components: {
    EmojiOrIcon,
    NextButton,
    InlineInput,
  },
  props: {
    href: {
      type: String,
      default: '',
    },
    icon: {
      type: String,
      required: true,
    },
    emoji: {
      type: String,
      required: true,
    },
    value: {
      type: String,
      default: '',
    },
    showCopy: {
      type: Boolean,
      default: false,
    },
    editable: {
      type: Boolean,
      default: false,
    },
    title: {
      type: String,
      default: '',
    },
  },
  emits: ['update'],
  data() {
    return {
      isEditing: false,
      editValue: '',
    };
  },
  methods: {
    async onCopy(e) {
      e.preventDefault();
      await copyTextToClipboard(this.value);
      useAlert(this.$t('CONTACT_PANEL.COPY_SUCCESSFUL'));
    },
    formatPhoneNumber(phone) {
      let digits = phone.replace(/\D/g, '');

      if (digits.length === 13) {
        // +55 DDD 9 XXXX-XXXX → remove DDI(2) + DDD(2) + 9
        digits = digits.slice(4);
        if (digits.length === 9) digits = digits.slice(1);
      } else if (digits.length === 12) {
        // +55 DDD XXXX-XXXX → remove DDI(2) + DDD(2)
        digits = digits.slice(4);
      } else if (digits.length === 11) {
        // DDD 9 XXXX-XXXX → remove DDD(2) + 9
        digits = digits.slice(2);
        if (digits.length === 9) digits = digits.slice(1);
      } else if (digits.length === 10) {
        // DDD XXXX-XXXX → remove DDD(2)
        digits = digits.slice(2);
      } else if (digits.length === 9) {
        // 9 XXXX-XXXX → remove 9
        digits = digits.slice(1);
      }

      if (digits.length === 8) {
        return `${digits.slice(0, 4)}-${digits.slice(4)}`;
      }
      return digits;
    },
    async onCopyFormatted(e) {
      e.preventDefault();
      const formatted = this.formatPhoneNumber(this.value);
      await copyTextToClipboard(formatted);
      useAlert(this.$t('CONTACT_PANEL.COPY_SUCCESSFUL'));
    },
    startEditing() {
      if (!this.editable) return;
      this.editValue = this.value || '';
      this.isEditing = true;
      this.$nextTick(() => {
        this.$refs.editInput?.focus();
      });
    },
    saveEdit() {
      if (!this.isEditing) return;
      this.isEditing = false;
      const trimmed = this.editValue.trim();
      if (trimmed !== (this.value || '')) {
        this.$emit('update', trimmed);
      }
    },
    cancelEdit() {
      this.isEditing = false;
    },
  },
};
</script>

<template>
  <div class="group/row w-full h-5 ltr:-ml-1 rtl:-mr-1">
    <!-- Inline edit mode -->
    <div v-if="isEditing" class="flex items-center w-full min-w-0 gap-2">
      <EmojiOrIcon
        :icon="icon"
        :emoji="emoji"
        icon-size="14"
        class="flex-shrink-0 ltr:ml-1 rtl:mr-1"
      />
      <InlineInput
        ref="editInput"
        v-model="editValue"
        :placeholder="title"
        @enter-press="saveEdit"
        @escape-press="cancelEdit"
        @blur="saveEdit"
      />
    </div>

    <!-- Read mode with link -->
    <a
      v-else-if="href"
      :href="href"
      class="flex items-center gap-2 text-n-slate-11 hover:underline"
    >
      <EmojiOrIcon
        :icon="icon"
        :emoji="emoji"
        icon-size="14"
        class="flex-shrink-0 ltr:ml-1 rtl:mr-1"
      />
      <span
        v-if="value"
        class="overflow-hidden text-sm whitespace-nowrap text-ellipsis"
        :title="value"
      >
        {{ value }}
      </span>
      <span v-else class="text-sm text-n-slate-11">
        {{ $t('CONTACT_PANEL.NOT_AVAILABLE') }}
      </span>
      <NextButton
        v-if="showCopy"
        ghost
        xs
        slate
        class="ltr:-ml-1 rtl:-mr-1"
        icon="i-lucide-clipboard"
        @click="onCopy"
      />
      <NextButton
        v-if="showCopy"
        ghost
        xs
        slate
        class="ltr:-ml-1 rtl:-mr-1"
        icon="i-lucide-brush"
        title="Copiar formatado (xxxx-xxxx)"
        @click="onCopyFormatted"
      />
      <NextButton
        v-if="editable"
        ghost
        xs
        slate
        class="ltr:-ml-1 rtl:-mr-1 opacity-0 group-hover/row:opacity-100 transition-opacity"
        icon="i-lucide-pencil"
        @click.prevent="startEditing"
      />
    </a>

    <!-- Read mode without link -->
    <div v-else class="flex items-center gap-2 text-n-slate-11">
      <EmojiOrIcon
        :icon="icon"
        :emoji="emoji"
        icon-size="14"
        class="flex-shrink-0 ltr:ml-1 rtl:mr-1"
      />
      <span
        v-if="value"
        v-dompurify-html="value"
        class="overflow-hidden text-sm whitespace-nowrap text-ellipsis"
      />
      <span v-else class="text-sm text-n-slate-11">
        {{ $t('CONTACT_PANEL.NOT_AVAILABLE') }}
      </span>
      <NextButton
        v-if="editable"
        ghost
        xs
        slate
        class="ltr:-ml-1 rtl:-mr-1 opacity-0 group-hover/row:opacity-100 transition-opacity"
        icon="i-lucide-pencil"
        @click="startEditing"
      />
    </div>
  </div>
</template>
