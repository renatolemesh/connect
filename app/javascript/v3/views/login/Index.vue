<script>
// utils and composables
import { login } from '../../api/auth';
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { required, email } from '@vuelidate/validators';
import { useVuelidate } from '@vuelidate/core';
import { SESSION_STORAGE_KEYS } from 'dashboard/constants/sessionStorage';
import SessionStorage from 'shared/helpers/sessionStorage';
import { useBranding } from 'shared/composables/useBranding';
import AnalyticsHelper from 'dashboard/helper/AnalyticsHelper';
import { SESSION_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import { getLoginRedirectURL } from 'v3/helpers/AuthHelper';

// components
import FormInput from '../../components/Form/Input.vue';
import Spinner from 'shared/components/Spinner.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import MfaVerification from 'dashboard/components/auth/MfaVerification.vue';
import MfaEnforcedSetup from 'dashboard/components/auth/MfaEnforcedSetup.vue';
import SessionLimitOverlay from 'dashboard/components/auth/SessionLimitOverlay.vue';

const ERROR_MESSAGES = {
  'no-account-found': 'LOGIN.OAUTH.NO_ACCOUNT_FOUND',
  'business-account-only': 'LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY',
  'shopify-installation-failed': 'LOGIN.OAUTH.SHOPIFY_INSTALLATION_FAILED',
  'saml-authentication-failed': 'LOGIN.SAML.API.ERROR_MESSAGE',
  'saml-not-enabled': 'LOGIN.SAML.API.ERROR_MESSAGE',
};

const IMPERSONATION_URL_SEARCH_KEY = 'impersonation';
const USER_NOT_CONFIRMED_ERROR_CODE = 'user_not_confirmed';
const AUTH_ERROR_TOAST_DURATION = 6000;

function startNeuralCanvas() {
  const canvas = document.getElementById('neural-canvas');
  if (!canvas) return;

  const ctx = canvas.getContext('2d');

  let particles = [];
  const particleCount = 60;
  const connectionDistance = 150;

  const resize = () => {
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;
  };

  window.addEventListener('resize', resize);
  resize();

  class Particle {
    constructor() {
      this.x = Math.random() * canvas.width;
      this.y = Math.random() * canvas.height;
      this.vx = (Math.random() - 0.5) * 0.35;
      this.vy = (Math.random() - 0.5) * 0.35;
    }

    update() {
      this.x += this.vx;
      this.y += this.vy;

      if (this.x < 0 || this.x > canvas.width) this.vx *= -1;
      if (this.y < 0 || this.y > canvas.height) this.vy *= -1;
    }
  }

  for (let i = 0; i < particleCount; i++) {
    particles.push(new Particle());
  }

  const animate = () => {
    ctx.fillStyle = '#020617';
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    particles.forEach((p, i) => {
      p.update();

      ctx.fillStyle = 'cyan';
      ctx.beginPath();
      ctx.arc(p.x, p.y, 2, 0, Math.PI * 2);
      ctx.fill();

      for (let j = i + 1; j < particles.length; j++) {
        const p2 = particles[j];
        const dist = Math.hypot(p.x - p2.x, p.y - p2.y);

        if (dist < connectionDistance) {
          ctx.strokeStyle = 'rgba(0,255,255,0.15)';
          ctx.beginPath();
          ctx.moveTo(p.x, p.y);
          ctx.lineTo(p2.x, p2.y);
          ctx.stroke();
        }
      }
    });

    requestAnimationFrame(animate);
  };

  animate();
}

export default {
  components: {
    FormInput,
    Spinner,
    NextButton,
    MfaVerification,
    MfaEnforcedSetup,
    SessionLimitOverlay,
  },
  props: {
    ssoAuthToken: { type: String, default: '' },
    ssoAccountId: { type: String, default: '' },
    ssoConversationId: { type: String, default: '' },
    email: { type: String, default: '' },
    authError: { type: String, default: '' },
    redirectUrl: { type: String, default: '' },
  },
  setup() {
    const { replaceInstallationName } = useBranding();
    return {
      replaceInstallationName,
      v$: useVuelidate(),
    };
  },
  data() {
    return {
      // We need to initialize the component with any
      // properties that will be used in it
      credentials: {
        email: '',
        password: '',
      },
      loginApi: {
        message: '',
        showLoading: false,
        hasErrored: false,
      },
      error: '',
      mfaRequired: false,
      mfaToken: null,
      mfaSetupRequired: false,
      mfaSetupToken: null,
      mfaProvisioningUrl: null,
      mfaSecret: null,
      verificationChannel: null,
      sessionsLimitReached: false,
      limitedSessions: [],
    };
  },
  validations() {
    return {
      credentials: {
        password: {
          required,
        },
        email: {
          required,
          email,
        },
      },
    };
  },
  computed: {
    ...mapGetters({ globalConfig: 'globalConfig/get' }),
  },
  created() {
    if (this.ssoAuthToken) {
      this.submitLogin();
    }
  },
  mounted() {
    startNeuralCanvas();
    if (this.authError) {
      // Wait for the sibling snackbar to mount and subscribe to toast events.
      this.$nextTick(() => {
        const messageKey = ERROR_MESSAGES[this.authError] ?? 'LOGIN.API.UNAUTH';
        // Use a method to get the translated text to avoid dynamic key warning
        const translatedMessage = this.getTranslatedMessage(messageKey);
        useAlert(translatedMessage, { duration: AUTH_ERROR_TOAST_DURATION });
        // wait for idle state
        this.requestIdleCallbackPolyfill(() => {
          // Remove the error query param from the url
          const { query } = this.$route;
          this.$router.replace({ query: { ...query, error: undefined } });
        });
      });
    }
  },
  methods: {
    getTranslatedMessage(key) {
      // Avoid dynamic key warning by handling each case explicitly
      switch (key) {
        case 'LOGIN.OAUTH.NO_ACCOUNT_FOUND':
          return this.$t('LOGIN.OAUTH.NO_ACCOUNT_FOUND');
        case 'LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY':
          return this.$t('LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY');
        case 'LOGIN.OAUTH.SHOPIFY_INSTALLATION_FAILED':
          return this.$t('LOGIN.OAUTH.SHOPIFY_INSTALLATION_FAILED');
        case 'LOGIN.API.UNAUTH':
        default:
          return this.$t('LOGIN.API.UNAUTH');
      }
    },
    // TODO: Remove this when Safari gets wider support
    // Ref: https://caniuse.com/requestidlecallback
    //
    requestIdleCallbackPolyfill(callback) {
      if (window.requestIdleCallback) {
        window.requestIdleCallback(callback);
      } else {
        // Fallback for safari
        // Using a delay of 0 allows the callback to be executed asynchronously
        // in the next available event loop iteration, similar to requestIdleCallback
        setTimeout(callback, 0);
      }
    },
    showAlertMessage(message) {
      // Reset loading, current selected agent
      this.loginApi.showLoading = false;
      this.loginApi.message = message;
      useAlert(this.loginApi.message);
    },
    handleImpersonation() {
      // Detects impersonation mode via URL and sets a session flag to prevent user settings changes during impersonation.
      const urlParams = new URLSearchParams(window.location.search);
      const impersonation = urlParams.get(IMPERSONATION_URL_SEARCH_KEY);
      if (impersonation) {
        SessionStorage.set(SESSION_STORAGE_KEYS.IMPERSONATION_USER, true);
      }
    },
    submitLogin() {
      this.loginApi.hasErrored = false;
      this.loginApi.showLoading = true;

      const credentials = {
        email: this.email
          ? decodeURIComponent(this.email)
          : this.credentials.email,
        password: this.credentials.password,
        sso_auth_token: this.ssoAuthToken,
        ssoAccountId: this.ssoAccountId,
        ssoConversationId: this.ssoConversationId,
        redirectUrl: this.redirectUrl,
      };

      login(credentials)
        .then(result => {
          // Check if MFA is required
          if (result?.mfaRequired) {
            this.loginApi.showLoading = false;
            this.mfaRequired = true;
            this.mfaToken = result.mfaToken;
            this.verificationChannel = result.verificationChannel || null;
            return;
          }

          // Check if the account enforces MFA and setup is pending
          if (result?.mfaSetupRequired) {
            this.loginApi.showLoading = false;
            this.mfaSetupRequired = true;
            this.mfaSetupToken = result.mfaSetupToken;
            this.mfaProvisioningUrl = result.provisioningUrl;
            this.mfaSecret = result.secret;
            return;
          }

          // Check if sessions limit reached
          if (result?.sessionsLimitReached) {
            this.loginApi.showLoading = false;
            this.sessionsLimitReached = true;
            this.limitedSessions = result.sessions;
            AnalyticsHelper.track(SESSION_EVENTS.LIMIT_HIT);
            return;
          }

          this.handleImpersonation();
          this.showAlertMessage(this.$t('LOGIN.API.SUCCESS_MESSAGE'));
        })
        .catch(response => {
          if (response?.errorCode === USER_NOT_CONFIRMED_ERROR_CODE) {
            this.loginApi.showLoading = false;
            this.$router.push({
              name: 'auth_verify_email',
              state: {
                email: credentials.email,
                redirectUrl: this.redirectUrl,
              },
            });
            return;
          }

          // Reset URL Params if the authentication is invalid
          if (this.email) {
            window.location = '/app/login';
          }
          this.loginApi.hasErrored = true;
          this.showAlertMessage(
            response?.message || this.$t('LOGIN.API.UNAUTH')
          );
        });
    },
    submitFormLogin() {
      if (this.v$.credentials.email.$invalid && !this.email) {
        this.showAlertMessage(this.$t('LOGIN.EMAIL.ERROR'));
        return;
      }

      this.submitLogin();
    },
    handleMfaVerified(user) {
      // Continue with the requested Shopify, account, or conversation destination.
      this.handleImpersonation();
      window.location = getLoginRedirectURL({
        ssoAccountId: this.ssoAccountId,
        ssoConversationId: this.ssoConversationId,
        redirectUrl: this.redirectUrl,
        user,
      });
    },
    handleMfaCancel() {
      // User cancelled MFA, reset state
      this.mfaRequired = false;
      this.mfaToken = null;
      this.verificationChannel = null;
      this.credentials.password = '';
    },
    // Device verification passed but the account still requires enrolment;
    // swap the challenge screen for the setup wizard.
    handleMfaSetupRequired(data) {
      this.mfaRequired = false;
      this.mfaToken = null;
      this.verificationChannel = null;
      this.mfaSetupRequired = true;
      this.mfaSetupToken = data.mfa_setup_token;
      this.mfaProvisioningUrl = data.provisioning_url;
      this.mfaSecret = data.secret;
    },
    handleMfaSetupVerified(data) {
      this.handleImpersonation();
      window.location = getLoginRedirectURL({
        ssoAccountId: this.ssoAccountId,
        ssoConversationId: this.ssoConversationId,
        redirectUrl: this.redirectUrl,
        user: data?.data,
      });
    },
    handleMfaSetupCancel() {
      this.mfaSetupRequired = false;
      this.mfaSetupToken = null;
      this.mfaProvisioningUrl = null;
      this.mfaSecret = null;
      this.credentials.password = '';
    },
    retryLoginWithParams(extraParams) {
      const credentials = {
        email: this.email
          ? decodeURIComponent(this.email)
          : this.credentials.email,
        password: this.credentials.password,
        sso_auth_token: this.ssoAuthToken,
        ssoAccountId: this.ssoAccountId,
        ssoConversationId: this.ssoConversationId,
        redirectUrl: this.redirectUrl,
        ...extraParams,
      };

      this.sessionsLimitReached = false;
      this.limitedSessions = [];
      this.loginApi.showLoading = true;
      login(credentials)
        .then(result => {
          if (result?.mfaRequired) {
            this.loginApi.showLoading = false;
            this.mfaRequired = true;
            this.mfaToken = result.mfaToken;
            this.verificationChannel = result.verificationChannel || null;
            return;
          }
          if (result?.sessionsLimitReached) {
            this.loginApi.showLoading = false;
            this.sessionsLimitReached = true;
            this.limitedSessions = result.sessions;
            AnalyticsHelper.track(SESSION_EVENTS.LIMIT_HIT);
            return;
          }
          this.handleImpersonation();
          this.showAlertMessage(this.$t('LOGIN.API.SUCCESS_MESSAGE'));
        })
        .catch(response => {
          this.loginApi.hasErrored = true;
          this.showAlertMessage(
            response?.message || this.$t('LOGIN.API.UNAUTH')
          );
        });
    },
    handleSessionRevoke(sessionId) {
      this.retryLoginWithParams({ revoke_session_id: sessionId });
    },
    handleSessionRevokeAll() {
      this.retryLoginWithParams({ revoke_all_sessions: true });
    },
    handleSessionLimitCancel() {
      this.sessionsLimitReached = false;
      this.limitedSessions = [];
      this.credentials.password = '';
    },
  },
};
</script>

<template>
  <main class="login-root flex flex-col w-full min-h-screen py-20 sm:px-6 lg:px-8">
    <canvas id="neural-canvas"></canvas>

    <section class="max-w-5xl mx-auto relative z-10">

      <img
        :src="globalConfig.logo"
        :alt="globalConfig.installationName"
        class="block w-auto h-8 mx-auto"
      />

      <h2 class="mt-6 text-3xl font-semibold text-center text-white neon-title">
        {{ replaceInstallationName($t('LOGIN.TITLE')) }}
      </h2>
    </section>

    <section
      v-if="sessionsLimitReached"
      class="login-card sm:mx-auto mt-11 sm:w-full sm:max-w-lg p-11"
    >
      <SessionLimitOverlay
        :sessions="limitedSessions"
        @revoke="handleSessionRevoke"
        @revoke-all="handleSessionRevokeAll"
        @cancel="handleSessionLimitCancel"
      />
    </section>

    <section
      v-else-if="mfaRequired"
      class="login-card sm:mx-auto mt-11 sm:w-full sm:max-w-lg p-11"
    >
      <MfaVerification
        :mfa-token="mfaToken"
        :verification-channel="verificationChannel"
        @verified="handleMfaVerified"
        @setup-required="handleMfaSetupRequired"
        @cancel="handleMfaCancel"
      />
    </section>

    <section
      v-else-if="mfaSetupRequired"
      class="login-card sm:mx-auto mt-11 sm:w-full sm:max-w-lg p-11"
    >
      <MfaEnforcedSetup
        :mfa-setup-token="mfaSetupToken"
        :provisioning-url="mfaProvisioningUrl"
        :secret="mfaSecret"
        @verified="handleMfaSetupVerified"
        @cancel="handleMfaSetupCancel"
      />
    </section>

    <section
      v-else
      class="login-card sm:mx-auto mt-11 sm:w-full sm:max-w-lg p-11"
    >
      <form v-if="!email" class="space-y-5" @submit.prevent="submitFormLogin">
        <FormInput
          v-model="credentials.email"
          name="email_address"
          type="text"
          required
          :label="$t('LOGIN.EMAIL.LABEL')"
          :placeholder="$t('LOGIN.EMAIL.PLACEHOLDER')"
          :has-error="v$.credentials.email.$error"
          @input="v$.credentials.email.$touch"
        />

        <FormInput
          v-model="credentials.password"
          type="password"
          name="password"
          required
          :label="$t('LOGIN.PASSWORD.LABEL')"
          :placeholder="$t('LOGIN.PASSWORD.PLACEHOLDER')"
          :has-error="v$.credentials.password.$error"
          @input="v$.credentials.password.$touch"
        />

        <NextButton
          lg
          type="submit"
          class="w-full"
          :label="$t('LOGIN.SUBMIT')"
          :disabled="loginApi.showLoading"
          :is-loading="loginApi.showLoading"
        />
      </form>
      <div v-else class="flex items-center justify-center">
        <Spinner color-scheme="primary" size="" />
      </div>
    </section>
  </main>
</template>

<style scoped>

.login-root{
  background:hsl(222,47%,5%);
  overflow:hidden;
  position:relative;
}

#neural-canvas{
  position:fixed;
  inset:0;
  width:100%;
  height:100%;
  z-index:0;
}

.neon-title{
  text-shadow:
    0 0 6px rgba(0,255,255,0.6),
    0 0 14px rgba(0,255,255,0.4),
    0 0 30px rgba(0,255,255,0.2);
}

.login-card{
  background:rgba(10,15,25,0.85);
  border-radius:22px;

  border:1px solid rgba(255,255,255,0.05);

  backdrop-filter:blur(25px);

  box-shadow:
    0 20px 80px rgba(0,0,0,0.9),
    0 0 30px rgba(0,255,255,0.08);

  position:relative;
  z-index:10;
}

</style>
