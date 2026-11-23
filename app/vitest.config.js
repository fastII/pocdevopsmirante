import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // Permite usar describe, it e expect sem importá-los.
    globals: true,

    // Localização dos arquivos de testes.
    include: ["tests/**/*.test.js"],

    coverage: {
      // Motor responsável por medir a cobertura.
      provider: "v8",

      // Formatos dos relatórios.
      reporter: ["text", "lcov", "json-summary"],

      // Diretório onde os relatórios serão gerados.
      reportsDirectory: "./coverage",

      // Código da aplicação que será analisado.
      include: ["src/**/*.js"],

      // Cobertura mínima exigida para aprovar a execução.
      thresholds: {
        lines: 80,
        functions: 80,
        branches: 80,
        statements: 80
      }
    }
  }
});