<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import fromUnixTime from 'date-fns/fromUnixTime';
import format from 'date-fns/format';
import BarChart from 'shared/components/charts/BarChart.vue';
import ReportsAPI from 'dashboard/api/reports';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import HelpIcon from './HelpIcon.vue';

const props = defineProps({
  filters: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();

const backlog = ref([]);
const isFetching = ref(false);

const fetchBacklog = () => {
  if (!props.filters.to || !props.filters.from) {
    return;
  }
  isFetching.value = true;
  ReportsAPI.getConversationBacklog(props.filters)
    .then(response => {
      backlog.value = response.data;
    })
    .catch(() => {
      useAlert(t('REPORT.DATA_FETCHING_FAILED'));
    })
    .finally(() => {
      isFetching.value = false;
    });
};

const chartData = computed(() => ({
  categories: backlog.value.map(point =>
    format(fromUnixTime(point.timestamp), 'dd-MMM')
  ),
  series: [
    {
      id: 'backlog',
      label: t('REPORT.BACKLOG.HEADER'),
      color: 'rgb(var(--blue-9))',
      data: backlog.value.map(point => point.value),
    },
  ],
}));

watch(() => props.filters, fetchBacklog, { deep: true });

onMounted(fetchBacklog);
</script>

<template>
  <div
    class="px-6 py-5 mt-4 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
  >
    <h3
      class="flex items-center gap-1 m-0 mb-4 text-sm font-medium text-n-slate-12"
    >
      {{ $t('REPORT.BACKLOG.HEADER') }}
      <HelpIcon :content="$t('REPORT.BACKLOG.DESCRIPTION')" />
    </h3>
    <div class="h-72">
      <woot-loading-state
        v-if="isFetching"
        class="text-xs"
        :message="$t('REPORT.LOADING_CHART')"
      />
      <div v-else class="flex items-center justify-center h-72">
        <BarChart
          v-if="backlog.length"
          :data="chartData"
          :aria-label="$t('REPORT.BACKLOG.HEADER')"
          :height="288"
          timeseries
        />
        <span v-else class="text-sm text-n-slate-10">
          {{ $t('REPORT.NO_ENOUGH_DATA') }}
        </span>
      </div>
    </div>
  </div>
</template>
