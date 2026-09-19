<script>
import V4Button from 'dashboard/components-next/button/Button.vue';
import { useAlert, useTrack } from 'dashboard/composables';
import ReportFilters from './components/ReportFilters.vue';
import ConversationFilter from './components/SLA/SLAFilter.vue';
import { parseFilterURLParams } from './helpers/reportFilterHelper';
import { GROUP_BY_FILTER } from './constants';
import { REPORTS_EVENTS } from '../../../../helper/AnalyticsHelper/events';
import { generateFileName } from 'dashboard/helper/downloadHelper';
import ReportContainer from './ReportContainer.vue';
import ReportHeader from './components/ReportHeader.vue';
import ResponseTimePercentiles from './components/ResponseTimePercentiles.vue';
import ConversationBacklog from './components/ConversationBacklog.vue';
import ConversationFunnel from './components/ConversationFunnel.vue';
import ResolutionReasons from './components/ResolutionReasons.vue';
import InboxStatusBreakdown from './components/InboxStatusBreakdown.vue';
import InboxLabelMatrix from './components/InboxLabelMatrix.vue';

const REPORTS_KEYS = {
  CONVERSATIONS: 'conversations_count',
  INCOMING_MESSAGES: 'incoming_messages_count',
  OUTGOING_MESSAGES: 'outgoing_messages_count',
  FIRST_RESPONSE_TIME: 'avg_first_response_time',
  RESOLUTION_TIME: 'avg_resolution_time',
  RESOLUTION_COUNT: 'resolutions_count',
  REPLY_TIME: 'reply_time',
};

export default {
  name: 'ConversationReports',
  components: {
    ReportHeader,
    ReportFilters,
    ConversationFilter,
    ReportContainer,
    ResponseTimePercentiles,
    ConversationBacklog,
    ConversationFunnel,
    ResolutionReasons,
    InboxStatusBreakdown,
    InboxLabelMatrix,
    V4Button,
  },
  data() {
    // Lidos ja aqui para que a primeira busca, disparada pelo ReportFilters, saia
    // com o recorte da URL em vez de buscar tudo e logo depois buscar de novo.
    const urlFilters = parseFilterURLParams(this.$route.query);
    return {
      from: 0,
      to: 0,
      groupBy: GROUP_BY_FILTER[1],
      businessHours: false,
      conversationFilters: {
        teamId: urlFilters.team_id,
        inboxId: urlFilters.inbox_id,
        assignedAgentId: urlFilters.agent_id,
        labelList: urlFilters.label,
      },
    };
  },
  computed: {
    reportFilters() {
      const { from, to, businessHours, conversationFilters } = this;
      return { from, to, businessHours, conversationFilters };
    },
  },
  mounted() {
    this.$store.dispatch('agents/get');
    this.$store.dispatch('inboxes/get');
    this.$store.dispatch('teams/get');
    this.$store.dispatch('labels/get');
  },
  methods: {
    fetchAllData() {
      this.fetchAccountSummary();
      this.fetchChartData();
    },
    fetchAccountSummary() {
      try {
        this.$store.dispatch('fetchAccountSummary', this.getRequestPayload());
      } catch {
        useAlert(this.$t('REPORT.SUMMARY_FETCHING_FAILED'));
      }
    },
    fetchChartData() {
      [
        'CONVERSATIONS',
        'INCOMING_MESSAGES',
        'OUTGOING_MESSAGES',
        'FIRST_RESPONSE_TIME',
        'RESOLUTION_TIME',
        'RESOLUTION_COUNT',
        'REPLY_TIME',
      ].forEach(async key => {
        try {
          await this.$store.dispatch('fetchAccountReport', {
            metric: REPORTS_KEYS[key],
            ...this.getRequestPayload(),
          });
        } catch {
          useAlert(this.$t('REPORT.DATA_FETCHING_FAILED'));
        }
      });
    },
    getRequestPayload() {
      const { from, to, groupBy, businessHours, conversationFilters } = this;

      return {
        from,
        to,
        groupBy: groupBy?.period,
        businessHours,
        conversationFilters,
      };
    },
    downloadConversationReports() {
      const { from, to } = this;
      const fileName = generateFileName({
        type: 'conversation',
        to,
        businessHours: this.businessHours,
      });
      this.$store.dispatch('downloadConversationsSummaryReports', {
        from,
        to,
        fileName,
        businessHours: this.businessHours,
        conversationFilters: this.conversationFilters,
      });
    },
    onConversationFilterChange(filters) {
      const next = {
        teamId: filters.team_id,
        inboxId: filters.inbox_id,
        assignedAgentId: filters.assigned_agent_id,
        labelList: filters.label_list,
      };
      const unchanged = Object.keys(next).every(
        key => (next[key] || null) === (this.conversationFilters[key] || null)
      );
      if (unchanged) return;

      this.conversationFilters = next;
      if (this.from && this.to) this.fetchAllData();
    },
    onFilterChange({ from, to, groupBy, businessHours }) {
      this.from = from;
      this.to = to;
      this.groupBy = groupBy;
      this.businessHours = businessHours;
      this.fetchAllData();

      useTrack(REPORTS_EVENTS.FILTER_REPORT, {
        filterValue: { from, to, groupBy, businessHours },
        reportType: 'conversations',
      });
    },
  },
};
</script>

<template>
  <ReportHeader :header-title="$t('REPORT.HEADER')">
    <V4Button
      :label="$t('REPORT.DOWNLOAD_CONVERSATION_REPORTS')"
      icon="i-ph-download-simple"
      size="sm"
      @click="downloadConversationReports"
    />
  </ReportHeader>
  <div class="flex flex-col">
    <ReportFilters
      :show-entity-filter="false"
      show-group-by
      @filter-change="onFilterChange"
    >
      <ConversationFilter
        :filter-types="['teams', 'inboxes', 'agents', 'labels']"
        dropdown-align="left"
        @filter-change="onConversationFilterChange"
      />
    </ReportFilters>
    <ReportContainer :group-by="groupBy" />
    <ResponseTimePercentiles :filters="reportFilters" />
    <ConversationBacklog :filters="reportFilters" />
    <ConversationFunnel :filters="reportFilters" />
    <ResolutionReasons :filters="reportFilters" />
    <InboxStatusBreakdown :filters="reportFilters" />
    <InboxLabelMatrix :filters="reportFilters" />
  </div>
</template>
