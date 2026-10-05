/* global axios */

import ApiClient from './ApiClient';

class WhatsappRetrySettings extends ApiClient {
  constructor() {
    super('whatsapp_retry_setting', { accountScoped: true });
  }

  // Recurso singular: a URL do ApiClient já aponta para o endpoint certo.
  get() {
    return axios.get(this.url);
  }

  update(payload) {
    return axios.patch(this.url, { whatsapp_retry_setting: payload });
  }

  // Simulação: aplica as mesmas regras e devolve o que seria reenviado agora,
  // sem tocar em nenhuma mensagem.
  preview() {
    return axios.post(`${this.url}/preview`);
  }
}

export default new WhatsappRetrySettings();
