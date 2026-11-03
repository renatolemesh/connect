<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useUISettings } from 'dashboard/composables/useUISettings';
import {
  SIGNATURE_POSITIONS,
  stripInlineBase64Images,
} from 'dashboard/helper/editorHelper';
import WootMessageEditor from 'dashboard/components/widgets/WootWriter/Editor.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import FormSelect from 'v3/components/Form/Select.vue';

const props = defineProps({
  messageSignature: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['updateSignature']);

const { t } = useI18n();
const signature = ref(props.messageSignature ?? '');
watch(
  () => props.messageSignature ?? '',
  newValue => {
    signature.value = newValue;
  }
);

const updateSignature = () => {
  const { sanitizedContent, hasInlineImages } = stripInlineBase64Images(
    signature.value || ''
  );
  signature.value = sanitizedContent.trim();
  if (hasInlineImages) {
    useAlert(
      t('PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.INLINE_IMAGE_WARNING')
    );
  }
  emit('updateSignature', signature.value);
};

const { signaturePosition, setSignaturePosition } = useUISettings();

const positionOptions = computed(() => [
  {
    id: SIGNATURE_POSITIONS.BOTTOM,
    name: t('PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.POSITION.BOTTOM'),
  },
  {
    id: SIGNATURE_POSITIONS.TOP,
    name: t('PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.POSITION.TOP'),
  },
]);

const selectedPosition = computed({
  get: () => signaturePosition.value,
  set: value => {
    setSignaturePosition(value);
    useAlert(
      t(
        'PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.POSITION.UPDATE_SUCCESS'
      )
    );
  },
});
</script>

<template>
  <form class="flex flex-col gap-6" @submit.prevent="updateSignature()">
    <div class="flex items-start justify-between w-full gap-2">
      <div>
        <label class="text-sm font-medium leading-6 text-n-gray-12">
          {{
            $t('PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.POSITION.TITLE')
          }}
        </label>
        <p class="text-n-gray-11">
          {{
            $t('PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.POSITION.NOTE')
          }}
        </p>
      </div>
      <FormSelect
        v-model="selectedPosition"
        name="signature_position"
        spacing="compact"
        class="mt-px min-w-40"
        :options="positionOptions"
        label=""
      >
        <option
          v-for="option in positionOptions"
          :key="option.id"
          :value="option.id"
          :selected="option.id === selectedPosition"
        >
          {{ option.name }}
        </option>
      </FormSelect>
    </div>
    <WootMessageEditor
      id="message-signature-input"
      v-model="signature"
      class="message-editor h-[10rem] !px-3"
      is-format-mode
      :placeholder="$t('PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE.PLACEHOLDER')"
      channel-type="Context::MessageSignature"
      :enable-suggestions="false"
    />
    <div>
      <NextButton
        type="submit"
        :label="$t('PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.BTN_TEXT')"
      />
    </div>
  </form>
</template>
