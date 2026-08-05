import { defineConfig } from "vite";

// Each window has its own HTML entry point. Vite builds them all into dist/.
export default defineConfig({
  root: "src",
  build: {
    outDir: "../dist",
    emptyOutDir: true,
    rollupOptions: {
      input: {
        popover: "src/popover.html",
        main: "src/main.html",
        settings: "src/settings.html",
        setup: "src/setup.html",
        "tunnel-edit": "src/tunnel-edit.html",
        logs: "src/logs.html",
      },
    },
  },
  clearScreen: false,
  server: {
    port: 17420,
    strictPort: true,
  },
});
