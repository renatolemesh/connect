import path from 'path';
import { defineConfig } from 'vite';
import ruby from 'vite-plugin-ruby';
import vue from '@vitejs/plugin-vue';
import { aliases, vueOptions } from './vite.shared';
import yaml from '@rollup/plugin-yaml';

const isLibraryMode = process.env.BUILD_MODE === 'library';
const isTestMode = process.env.TEST === 'true';
const isDevelopment = process.env.NODE_ENV === 'development';

let plugins = [ruby(), vue(vueOptions), yaml()];

if (isLibraryMode) {
  plugins = [];
} else if (isTestMode) {
  plugins = [vue(vueOptions), yaml()];
}

export default defineConfig({
  base: '/vite-dev/',
  plugins: plugins,

  css: {
    preprocessorOptions: {
      scss: {
        api: 'modern-compiler',
      },
    },
  },
  
  // ============================================================================
  // OPTIMIZATIONS FOR DEVELOPMENT HMR
  // ============================================================================
  server: isDevelopment ? {
    // Host configuration for Docker
    host: '0.0.0.0',
    port: Number(process.env.VITE_RUBY_PORT) || 3036,
    strictPort: true,
    allowedHosts: true,
    
    // HMR configuration optimized for Docker
    hmr: {
      // Use the host that the browser should connect to
      host: process.env.VITE_RUBY_HMR_HOST || 'localhost',
      port: Number(process.env.VITE_RUBY_PORT) || 3036,
      // Behind a TLS-terminating proxy the browser reaches HMR at wss://host:443,
      // not ws://host:3036. clientPort is what the client is told to dial;
      // port above stays the port the dev server actually listens on.
      clientPort: Number(process.env.VITE_HMR_CLIENT_PORT) || 3036,
      // Use native WebSocket instead of polling
      protocol: process.env.VITE_HMR_PROTOCOL || 'ws',
    },
    
    // Watch configuration for better file change detection
    watch: {
      // Use native file system events (not polling) for better performance
      usePolling: process.env.CHOKIDAR_USEPOLLING === 'true',
      // Reduce CPU usage by increasing poll interval if polling is enabled
      interval: 300,
      // Ignore heavy directories to reduce watch overhead
      ignored: [
        '**/node_modules/**',
        '**/vendor/**',
        '**/tmp/**',
        '**/log/**',
        '**/.git/**',
        '**/coverage/**',
        '**/public/packs/**',
        '**/docker_data/**',
      ],
    },
    
    // CORS for cross-origin requests
    cors: true,
    
    // Optimize dependency pre-bundling
    fs: {
      // Allow serving files from the project root and node_modules
      allow: ['.', 'node_modules'],
    },
  } : undefined,
  
  // ============================================================================
  // DEPENDENCY OPTIMIZATION
  // ============================================================================
  optimizeDeps: {
    include: [
      'vue',
      'vue-router',
      'vuex',
      'axios',
      'pinia',
      'vue-i18n',
      '@vueuse/core',
      '@vueuse/components',
      '@chatwoot/viz',
      'date-fns',
      'dompurify',
      'highlight.js',
      'linkify-it',
      'js-cookie',
      'lodash',
      'floating-vue',
      'vuex-router-sync',
      'vue-dompurify-html',
      '@sentry/vue',
      '@highlightjs/vue-plugin',
      '@formkit/vue',
      '@amplitude/analytics-browser',
      '@amplitude/analytics-core',
      'lit',
      'lit/decorators.js',
      'lit/directives/class-map.js',
      'lit/directives/ref.js',
      'lit/directives/unsafe-html.js',
      'lit/directives/join.js',
      '@material/mwc-icon',
      'tslib',
      '@chatwoot/ninja-keys',
      '@kurkle/color',
      'vue3-click-away',
    ],
    exclude: ['@chatwoot/prosemirror-schema'],
    force: true,
    esbuildOptions: {
      logLevel: 'error',
      target: 'es2020',
      nodePaths: ['node_modules'],
      // IMPORTANT: remove defaultLoader completely, esbuild 0.21.5 doesn't support it
    },
  },
  
  // ============================================================================
  // BUILD CONFIGURATION
  // ============================================================================
  build: {
    // Increase chunk size warning limit to avoid warnings
    chunkSizeWarningLimit: 1000,
    
    // Enable source maps in development for better debugging
    sourcemap: isDevelopment ? 'inline' : false,
    
    // Optimize build output
    minify: !isDevelopment ? 'esbuild' : false,
    
    // Target modern browsers for smaller bundle size
    target: 'es2020',
    
    rollupOptions: {
      output: {
        // [NOTE] when not in library mode, no new keys will be addedd or overwritten
        // setting dir: isLibraryMode ? 'public/packs' : undefined will not work
        ...(isLibraryMode
          ? {
              dir: 'public/packs',
              entryFileNames: chunkInfo => {
                if (chunkInfo.name === 'sdk') {
                  return 'js/sdk.js';
                }
                return '[name].js';
              },
            }
          : {}),
        inlineDynamicImports: isLibraryMode, // Disable code-splitting for SDK
        
        // Optimize chunk splitting for better caching
        manualChunks: !isLibraryMode ? {
          // Separate vendor chunks for better caching
          'vue-vendor': ['vue', 'vue-router', 'vuex', 'pinia'],
          'chart-vendor': ['@chatwoot/viz'],
          'ui-vendor': ['@vueuse/core', '@vueuse/components'],
        } : undefined,
      },
    },
    
    lib: isLibraryMode
      ? {
          entry: path.resolve(__dirname, './app/javascript/entrypoints/sdk.js'),
          formats: ['iife'], // IIFE format for single file
          name: 'sdk',
        }
      : undefined,
  },
  
  // ============================================================================
  // TEST CONFIGURATION
  // ============================================================================
  test: {
    environment: 'jsdom',
    include: ['app/**/*.{test,spec}.?(c|m)[jt]s?(x)'],
    coverage: {
      reporter: ['lcov', 'text'],
      include: ['app/**/*.js', 'app/**/*.vue'],
      exclude: [
        'app/**/*.@(spec|stories|routes).js',
        '**/specs/**/*',
        '**/i18n/**/*',
      ],
    },
    globals: true,
    outputFile: 'coverage/sonar-report.xml',
    pool: 'threads',
    poolOptions: {
      threads: {
        singleThread: false,
      },
    },
    server: {
      deps: {
        inline: ['tinykeys', '@material/mwc-icon'],
      },
    },
    setupFiles: ['fake-indexeddb/auto', 'vitest.setup.js'],
    mockReset: true,
    clearMocks: true,
  },
  resolve: { alias: aliases, preserveSymlinks: true },
});
