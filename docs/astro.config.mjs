import { defineConfig } from 'astro/config';

export default defineConfig({
  publicDir: 'assets',
  markdown: {
    shikiConfig: {
      themes: {
        light: 'github-light',
        dark: 'github-dark'
      },
      defaultColor: false,
      wrap: true
    }
  },
  server: {
    host: true,
    port: 4321
  }
});
