import { createSharedComposable, useMediaQuery } from '@vueuse/core';

// Celular e tablet sem mouse: nao ha hover, clique direito nem atalho de teclado.
// Compartilhado porque cada balao de mensagem consulta: uma media query so.
export const useTouchDevice = createSharedComposable(() =>
  useMediaQuery('(hover: none) and (pointer: coarse)')
);
