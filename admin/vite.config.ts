import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  // VITE_BASE_PATH=/admin/ builds the panel to be served by the API under /admin (D-060).
  base: process.env.VITE_BASE_PATH ?? '/',
  plugins: [react(), tailwindcss()],
  server: { port: 5173 },
  // `vite preview` serves the production build when the panel is exposed through an ngrok tunnel.
  preview: { port: 4173, allowedHosts: ['.ngrok-free.dev', '.ngrok-free.app'] },
});
