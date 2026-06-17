import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = fileURLToPath(new URL('.', import.meta.url))

// https://vite.dev/config/
export default defineConfig({
  base: '/',
  plugins: [react(), tailwindcss()],
  // allow importing ../CHANGELOG.md?raw from the repo root in dev
  server: { fs: { allow: ['..'] } },
  build: {
    rollupOptions: {
      input: {
        main: resolve(root, 'index.html'),
        changelog: resolve(root, 'changelog/index.html'),
      },
    },
  },
})
