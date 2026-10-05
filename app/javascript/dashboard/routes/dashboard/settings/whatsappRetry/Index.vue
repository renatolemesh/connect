<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import WhatsappRetrySettingsAPI from 'dashboard/api/whatsappRetrySettings';
import Input from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';

const { t } = useI18n();

const isLoading = ref(true);
const isSaving = ref(false);
const isPreviewing = ref(false);
const availableInboxes = ref([]);
const lastRunAt = ref(null);
const lastRunSummary = ref({});
const preview = ref(null);

const form = ref({
  enabled: false,
  maxAttempts: 3,
  maxPerRun: 50,
  inboxIds: [],
  transient: { codes: '', delays: '', maxAge: 24 },
  slow: { codes: '', delays: '', maxAge: 96 },
  neverCodes: '',
});

// A config viaja como listas no JSON e é editada como texto separado por vírgula.
const toList = value =>
  String(value || '')
    .split(',')
    .map(entry => entry.trim())
    .filter(Boolean);

const toNumberList = value => toList(value).map(Number).filter(Boolean);

const fromList = list => (list || []).join(', ');

const applyConfig = data => {
  const config = data.config || {};
  form.value = {
    enabled: data.enabled,
    maxAttempts: config.max_attempts,
    maxPerRun: config.max_per_run,
    inboxIds: config.inbox_ids || [],
    transient: {
      codes: fromList(config.transient?.codes),
      delays: fromList(config.transient?.delays_minutes),
      maxAge: config.transient?.max_age_hours,
    },
    slow: {
      codes: fromList(config.slow?.codes),
      delays: fromList(config.slow?.delays_minutes),
      maxAge: config.slow?.max_age_hours,
    },
    neverCodes: fromList(config.never_codes),
  };
  availableInboxes.value = data.available_inboxes || [];
  lastRunAt.value = data.last_run_at;
  lastRunSummary.value = data.last_run_summary || {};
};

const buildPayload = () => ({
  enabled: form.value.enabled,
  config: {
    max_attempts: Number(form.value.maxAttempts),
    max_per_run: Number(form.value.maxPerRun),
    inbox_ids: form.value.inboxIds,
    transient: {
      codes: toList(form.value.transient.codes),
      delays_minutes: toNumberList(form.value.transient.delays),
      max_age_hours: Number(form.value.transient.maxAge),
    },
    slow: {
      codes: toList(form.value.slow.codes),
      delays_minutes: toNumberList(form.value.slow.delays),
      max_age_hours: Number(form.value.slow.maxAge),
    },
    never_codes: toList(form.value.neverCodes),
  },
});

const fetchSettings = async () => {
  try {
    const { data } = await WhatsappRetrySettingsAPI.get();
    applyConfig(data);
  } catch (error) {
    useAlert(t('WHATSAPP_RETRY.API.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const save = async () => {
  isSaving.value = true;
  try {
    const { data } = await WhatsappRetrySettingsAPI.update(buildPayload());
    applyConfig(data);
    useAlert(t('WHATSAPP_RETRY.API.SAVE_SUCCESS'));
  } catch (error) {
    useAlert(
      error?.response?.data?.message || t('WHATSAPP_RETRY.API.SAVE_ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};

// Simular salva antes, para que a prévia reflita o que está na tela.
const runPreview = async () => {
  isPreviewing.value = true;
  try {
    await WhatsappRetrySettingsAPI.update(buildPayload());
    const { data } = await WhatsappRetrySettingsAPI.preview();
    preview.value = data;
  } catch (error) {
    useAlert(t('WHATSAPP_RETRY.API.PREVIEW_ERROR'));
  } finally {
    isPreviewing.value = false;
  }
};

const toggleInbox = id => {
  const list = form.value.inboxIds;
  form.value.inboxIds = list.includes(id)
    ? list.filter(item => item !== id)
    : [...list, id];
};

const skippedEntries = computed(() =>
  Object.entries(preview.value?.skipped_by_reason || {})
);

onMounted(fetchSettings);
</script>

<template>
  <SettingsLayout
    :is-loading="isLoading"
    :loading-message="$t('WHATSAPP_RETRY.LOADING')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="$t('WHATSAPP_RETRY.HEADER.TITLE')"
        :description="$t('WHATSAPP_RETRY.HEADER.DESCRIPTION')"
      />
    </template>

    <template #body>
      <div class="flex flex-col gap-6 max-w-3xl pb-8">
        <div
          class="flex items-center justify-between gap-4 p-4 rounded-lg bg-n-alpha-black2"
        >
          <div class="flex flex-col gap-1">
            <span class="text-sm font-medium text-n-slate-12">
              {{ $t('WHATSAPP_RETRY.ENABLED.LABEL') }}
            </span>
            <span class="text-sm text-n-slate-11">
              {{ $t('WHATSAPP_RETRY.ENABLED.HELP') }}
            </span>
          </div>
          <Switch v-model="form.enabled" />
        </div>

        <div class="grid grid-cols-2 gap-4">
          <Input
            v-model="form.maxAttempts"
            type="number"
            :label="$t('WHATSAPP_RETRY.MAX_ATTEMPTS.LABEL')"
            :message="$t('WHATSAPP_RETRY.MAX_ATTEMPTS.HELP')"
          />
          <Input
            v-model="form.maxPerRun"
            type="number"
            :label="$t('WHATSAPP_RETRY.MAX_PER_RUN.LABEL')"
            :message="$t('WHATSAPP_RETRY.MAX_PER_RUN.HELP')"
          />
        </div>

        <div class="flex flex-col gap-2">
          <span class="text-sm font-medium text-n-slate-12">
            {{ $t('WHATSAPP_RETRY.INBOXES.LABEL') }}
          </span>
          <span class="text-sm text-n-slate-11">
            {{ $t('WHATSAPP_RETRY.INBOXES.HELP') }}
          </span>
          <div class="flex flex-wrap gap-2 mt-1">
            <button
              v-for="inbox in availableInboxes"
              :key="inbox.id"
              type="button"
              class="px-3 py-1.5 text-sm rounded-lg outline outline-1 outline-offset-[-1px]"
              :class="
                form.inboxIds.includes(inbox.id)
                  ? 'bg-n-brand/10 outline-n-brand text-n-slate-12'
                  : 'outline-n-weak text-n-slate-11'
              "
              @click="toggleInbox(inbox.id)"
            >
              {{ inbox.name }}
              <span class="text-n-slate-10">
                {{
                  inbox.official
                    ? $t('WHATSAPP_RETRY.INBOXES.OFFICIAL')
                    : $t('WHATSAPP_RETRY.INBOXES.UNOFFICIAL')
                }}
              </span>
            </button>
          </div>
        </div>

        <div
          class="flex flex-col gap-3 p-4 rounded-lg outline outline-1 outline-offset-[-1px] outline-n-weak"
        >
          <span class="text-sm font-medium text-n-slate-12">
            {{ $t('WHATSAPP_RETRY.TRANSIENT.TITLE') }}
          </span>
          <span class="text-sm text-n-slate-11">
            {{ $t('WHATSAPP_RETRY.TRANSIENT.HELP') }}
          </span>
          <Input
            v-model="form.transient.codes"
            :label="$t('WHATSAPP_RETRY.CODES.LABEL')"
            :message="$t('WHATSAPP_RETRY.CODES.HELP')"
          />
          <div class="grid grid-cols-2 gap-4">
            <Input
              v-model="form.transient.delays"
              :label="$t('WHATSAPP_RETRY.DELAYS.LABEL')"
              :message="$t('WHATSAPP_RETRY.DELAYS.HELP')"
            />
            <Input
              v-model="form.transient.maxAge"
              type="number"
              :label="$t('WHATSAPP_RETRY.MAX_AGE.LABEL')"
              :message="$t('WHATSAPP_RETRY.MAX_AGE.HELP')"
            />
          </div>
        </div>

        <div
          class="flex flex-col gap-3 p-4 rounded-lg outline outline-1 outline-offset-[-1px] outline-n-weak"
        >
          <span class="text-sm font-medium text-n-slate-12">
            {{ $t('WHATSAPP_RETRY.SLOW.TITLE') }}
          </span>
          <span class="text-sm text-n-slate-11">
            {{ $t('WHATSAPP_RETRY.SLOW.HELP') }}
          </span>
          <Input
            v-model="form.slow.codes"
            :label="$t('WHATSAPP_RETRY.CODES.LABEL')"
            :message="$t('WHATSAPP_RETRY.CODES.HELP')"
          />
          <div class="grid grid-cols-2 gap-4">
            <Input
              v-model="form.slow.delays"
              :label="$t('WHATSAPP_RETRY.DELAYS.LABEL')"
              :message="$t('WHATSAPP_RETRY.DELAYS.HELP')"
            />
            <Input
              v-model="form.slow.maxAge"
              type="number"
              :label="$t('WHATSAPP_RETRY.MAX_AGE.LABEL')"
              :message="$t('WHATSAPP_RETRY.MAX_AGE.HELP')"
            />
          </div>
        </div>

        <Input
          v-model="form.neverCodes"
          :label="$t('WHATSAPP_RETRY.NEVER.LABEL')"
          :message="$t('WHATSAPP_RETRY.NEVER.HELP')"
        />

        <div class="flex items-center gap-3">
          <NextButton
            :label="$t('WHATSAPP_RETRY.SAVE')"
            :is-loading="isSaving"
            @click="save"
          />
          <NextButton
            faded
            slate
            :label="$t('WHATSAPP_RETRY.PREVIEW')"
            :is-loading="isPreviewing"
            @click="runPreview"
          />
        </div>

        <div
          v-if="preview"
          class="flex flex-col gap-2 p-4 rounded-lg bg-n-alpha-black2"
        >
          <span class="text-sm font-medium text-n-slate-12">
            {{ $t('WHATSAPP_RETRY.PREVIEW_RESULT.TITLE') }}
          </span>
          <span class="text-sm text-n-slate-11">
            {{
              $t('WHATSAPP_RETRY.PREVIEW_RESULT.SUMMARY', {
                examined: preview.examined,
                retried: preview.retried,
              })
            }}
          </span>
          <ul v-if="skippedEntries.length" class="mt-1 text-sm text-n-slate-11">
            <li v-for="[reason, count] in skippedEntries" :key="reason">
              {{ count }} — {{ $t(`WHATSAPP_RETRY.REASONS.${reason}`) }}
            </li>
          </ul>
        </div>

        <div v-if="lastRunAt" class="text-sm text-n-slate-11">
          {{
            $t('WHATSAPP_RETRY.LAST_RUN', {
              at: lastRunAt,
              retried: lastRunSummary.retried || 0,
              examined: lastRunSummary.examined || 0,
            })
          }}
        </div>
      </div>
    </template>
  </SettingsLayout>
</template>
