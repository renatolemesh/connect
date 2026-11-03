<script>
// utils and composables
import { login } from '../../api/auth';
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { required, email } from '@vuelidate/validators';
import { useVuelidate } from '@vuelidate/core';
import { useBranding } from 'shared/composables/useBranding';

// components
import SimpleDivider from '../../components/Divider/SimpleDivider.vue';
import FormInput from '../../components/Form/Input.vue';
import GoogleOAuthButton from '../../components/GoogleOauth/Button.vue';
import Spinner from 'shared/components/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import MfaVerification from 'dashboard/components/auth/MfaVerification.vue';

export default {
  components: {
    FormInput,
    GoogleOAuthButton,
    Spinner,
    NextButton,
    SimpleDivider,
    MfaVerification,
    Icon,
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
      credentials: {
        email: '',
        password: '',
      },
      loginApi: {
        message: '',
        showLoading: false,
        hasErrored: false,
      },
      mfaRequired: false,
      mfaToken: null,
    };
  },

  validations() {
    return {
      credentials: {
        password: { required },
        email: { required, email },
      },
    };
  },

  computed: {
    ...mapGetters({ globalConfig: 'globalConfig/get' }),
  },

  methods: {
    submitFormLogin() {
      if (this.v$.credentials.email.$invalid) {
        useAlert(this.$t('LOGIN.EMAIL.ERROR'));
        return;
      }

      this.loginApi.showLoading = true;

      login(this.credentials)
        .then(result => {
          // Quando o backend pede segundo fator, login() NAO redireciona:
          // devolve { mfaRequired, mfaToken } e espera a verificacao.
          // Redirecionar aqui era o que mantinha o MFA quebrado.
          if (result?.mfaRequired) {
            this.loginApi.showLoading = false;
            this.mfaRequired = true;
            this.mfaToken = result.mfaToken;
            return;
          }
          // Idem para o limite de sessoes. Este login ainda nao mostra a
          // tela de revogacao, entao avisamos em vez de cair num bounce.
          if (result?.sessionsLimitReached) {
            this.loginApi.showLoading = false;
            useAlert(this.$t('LOGIN.API.UNAUTH'));
            return;
          }
          window.location = '/app';
        })
        .catch(() => {
          this.loginApi.showLoading = false;
          useAlert(this.$t('LOGIN.API.UNAUTH'));
        });
    },
    handleMfaVerified() {
      // MfaVerification ja gravou as credenciais no emit 'verified'.
      window.location = '/app';
    },
    handleMfaCancel() {
      this.mfaRequired = false;
      this.mfaToken = null;
      this.credentials.password = '';
    },
  },

  mounted() {
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
      v-if="mfaRequired"
      class="login-card sm:mx-auto mt-11 sm:w-full sm:max-w-lg p-11"
    >
      <MfaVerification
        :mfa-token="mfaToken"
        @verified="handleMfaVerified"
        @cancel="handleMfaCancel"
      />
    </section>

    <section
      v-else
      class="login-card sm:mx-auto mt-11 sm:w-full sm:max-w-lg p-11"
    >
      <form class="space-y-5" @submit.prevent="submitFormLogin">

        <FormInput
          v-model="credentials.email"
          type="text"
          required
          :label="$t('LOGIN.EMAIL.LABEL')"
          :placeholder="$t('LOGIN.EMAIL.PLACEHOLDER')"
        />

        <FormInput
          v-model="credentials.password"
          type="password"
          required
          :label="$t('LOGIN.PASSWORD.LABEL')"
          :placeholder="$t('LOGIN.PASSWORD.PLACEHOLDER')"
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
