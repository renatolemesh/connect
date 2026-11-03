<script setup>
import { ref, computed, watch } from 'vue';
import fromUnixTime from 'date-fns/fromUnixTime';
import format from 'date-fns/format';
import { formatTime } from '@chatwoot/utils';
import BarChart from 'shared/components/charts/BarChart.vue';
import ReportsAPI from 'dashboard/api/reports';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import HelpIcon from './HelpIcon.vue';
import {
  COMPARISON_COLORS,
  COMPARISON_METRICS,
  MAX_COMPARISON_ENTITIES,
} from '../constants';

const props = defineProps({
  type: {
    type: String,
    required: true,
  },
  items: {
    type: Array,
    default: () => [],
  },
  filters: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();

const selectedIds = ref([]);
const metric = ref(COMPARISON_METRICS[0].key);
const series = ref({});
const isFetching = ref(false);

const isTimeMetric = computed(() => metric.value.startsWith('avg_'));

const nameOf = id => {
  const item = props.items.find(entry => entry.id === id);
  return item?.name ?? item?.title ?? String(id);
};

const canSelectMore = computed(
  () => selectedIds.value.length < MAX_COMPARISON_ENTITIES
);

const isSelected = id => selectedIds.value.includes(id);

const toggleEntity = id => {
  if (isSelected(id)) {
    selectedIds.value = selectedIds.value.filter(entry => entry !== id);
  } else if (canSelectMore.value) {
    selectedIds.value = [...selectedIds.value, id];
  }
};

const fetchSeries = async () => {
  if (!props.filters.from || !props.filters.to || !selectedIds.value.length) {
    series.value = {};
    return;
  }
  isFetching.value = true;
  try {
    const responses = await Promise.all(
      selectedIds.value.map(id =>
        ReportsAPI.getReports({
          metric: metric.value,
          from: props.filters.from,
          to: props.filters.to,
          type: props.type,
          id,
          groupBy: 'day',
          businessHours: props.filters.businessHours,
        })
      )
    );
    series.value = Object.fromEntries(
      selectedIds.value.map((id, index) => [id, responses[index].data])
    );
  } catch {
    useAlert(t('REPORT.DATA_FETCHING_FAILED'));
  } finally {
    isFetching.value = false;
  }
};

const chartData = computed(() => {
  const first = series.value[selectedIds.value[0]] ?? [];
  return {
    categories: first.map(point =>
      format(fromUnixTime(point.timestamp), 'dd-MMM')
    ),
    series: selectedIds.value.map((id, index) => ({
      id: String(id),
      label: nameOf(id),
      color: COMPARISON_COLORS[index],
      data: (series.value[id] ?? []).map(point => Number(point.value)),
    })),
  };
});

const formatValue = value =>
  isTimeMetric.value ? formatTime(value || 0) : Number(value).toLocaleString();

const hasData = computed(() =>
  selectedIds.value.some(id => (series.value[id] ?? []).length)
);

watch([selectedIds, metric, () => props.filters], fetchSeries, { deep: true });
</script>

<template>
  <div
    class="px-6 py-5 mt-4 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
  >
    <h3
      class="flex items-center gap-1 m-0 mb-4 text-sm font-medium text-n-slate-12"
    >
      {{ $t('REPORT.COMPARISON.HEADER') }}
      <HelpIcon
        :content="
          $t('REPORT.COMPARISON.DESCRIPTION', { max: MAX_COMPARISON_ENTITIES })
        "
      />
    </h3>

    <div class="flex flex-wrap gap-2 mb-3">
      <button
        v-for="option in COMPARISON_METRICS"
        :key="option.key"
        type="button"
        class="px-2 py-1 text-xs rounded-md"
        :class="
          metric === option.key
            ? 'bg-n-brand text-white'
            : 'bg-n-solid-3 text-n-slate-11'
        "
        @click="metric = option.key"
      >
        {{ $t(option.translationKey) }}
      </button>
    </div>

    <div class="flex flex-wrap gap-2 pt-3 mb-4 border-t border-n-container">
      <button
        v-for="item in items"
        :key="item.id"
        type="button"
        class="px-2 py-1 text-xs rounded-md"
        :class="
          isSelected(item.id)
            ? 'bg-n-slate-12 text-n-solid-1'
            : 'bg-n-solid-3 text-n-slate-11'
        "
        :disabled="!isSelected(item.id) && !canSelectMore"
        :title="
          !isSelected(item.id) && !canSelectMore
            ? $t('REPORT.COMPARISON.LIMIT_REACHED', {
                max: MAX_COMPARISON_ENTITIES,
              })
            : ''
        "
        @click="toggleEntity(item.id)"
      >
        {{ item.name ?? item.title }}
      </button>
    </div>

    <div class="h-72">
      <woot-loading-state
        v-if="isFetching"
        class="text-xs"
        :message="$t('REPORT.LOADING_CHART')"
      />
      <div v-else class="flex items-center justify-center h-72">
        <BarChart
          v-if="hasData"
          :data="chartData"
          :aria-label="$t('REPORT.COMPARISON.HEADER')"
          :format-value="formatValue"
          :height="288"
          timeseries
        />
        <span v-else class="text-sm text-center text-n-slate-10">
          {{ $t('REPORT.COMPARISON.EMPTY') }}
        </span>
      </div>
    </div>
    <!-- O BarChart do viz nao tem legenda, e sem ela as cores nao dizem de quem e
    cada barra, que e o ponto do grafico. -->
    <ul
      v-if="!isFetching && hasData"
      class="flex flex-wrap justify-center gap-x-4 gap-y-1 m-0 mt-2 list-none text-xs text-n-slate-11"
    >
      <li
        v-for="(id, index) in selectedIds"
        :key="id"
        class="flex items-center gap-1.5"
      >
        <span
          class="rounded-sm size-2.5"
          :style="{ backgroundColor: COMPARISON_COLORS[index] }"
        />
        {{ nameOf(id) }}
      </li>
    </ul>
  </div>
</template>
