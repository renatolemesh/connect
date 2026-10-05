import { frontendURL } from '../../../../helper/URLHelper';

import SettingsWrapper from '../SettingsWrapper.vue';
import WhatsappRetryHome from './Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/whatsapp-retry'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          redirect: to => {
            return { name: 'whatsapp_retry_settings', params: to.params };
          },
        },
        {
          path: 'index',
          name: 'whatsapp_retry_settings',
          meta: {
            permissions: ['administrator'],
          },
          component: WhatsappRetryHome,
        },
      ],
    },
  ],
};
