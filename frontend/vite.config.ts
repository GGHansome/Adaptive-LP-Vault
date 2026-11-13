import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
export default defineConfig(({ mode }) => ({
  plugins: [react()],
  // Deployment acceptance rewrites the public manifest between independent browser contexts.
  // Keep the wallet configuration stable within each context; ordinary development retains HMR.
  server: { hmr: mode === 'deployment-test' ? false : undefined },
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
    exclude: ['node_modules/**', 'dist/**'],
  },
  build: { chunkSizeWarningLimit: 1200 },
}));
