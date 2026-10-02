import { defineConfig } from 'vite';

export default defineConfig({
  // Relative asset paths so the built bundle works from Capacitor's
  // capacitor://localhost origin as well as any static host.
  base: './',
  server: {
    host: true,
    port: 5173,
  },
  build: {
    target: 'es2022',
    sourcemap: true,
  },
});
