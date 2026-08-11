import { defineConfig } from 'vitest/config';

export default defineConfig({
  root: process.cwd(),
  test: {
    coverage: {
      enabled: false,
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
    },
    environment: 'node',
    passWithNoTests: true,
    restoreMocks: true,
  },
});
