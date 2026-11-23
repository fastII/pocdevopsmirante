
"use strict";

// Importa a função responsável por criar o servidor HTTP.
// O servidor não será iniciado automaticamente durante os testes.
const { createServer } = require("../src/server");

// Obtém a versão da aplicação definida no package.json.
const { version } = require("../package.json");

// describe, it e expect são disponibilizados automaticamente
// pelo Vitest através da configuração globals: true.

/**
 * Executa uma requisição HTTP contra uma instância
 * temporária do servidor da aplicação.
 *
 * A porta é escolhida automaticamente pelo sistema operacional,
 * evitando conflitos com outros serviços.
 *
 * @param {string} path - Endpoint que será testado.
 * @param {string} method - Método HTTP (GET, POST etc.).
 * @returns {Promise<object>} Status, headers e corpo da resposta.
 */
async function request(path, method = "GET") {
  // Cria uma nova instância HTTP para cada teste.
  const server = createServer();

  // Inicializa o servidor em uma porta dinâmica.
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });

  try {
    // Recupera a porta atribuída pelo sistema operacional.
    const address = server.address();

    // Executa uma requisição HTTP real contra a aplicação.
    const response = await fetch(
      `http://127.0.0.1:${address.port}${path}`,
      { method }
    );

    // Retorna os dados necessários para as validações.
    return {
      status: response.status,
      headers: response.headers,
      body: await response.json()
    };
  } finally {
    // Encerra o servidor após cada teste.
    // Isso evita portas abertas e processos pendentes.
    await new Promise((resolve, reject) => {
      server.close((error) => {
        if (error) {
          reject(error);
        } else {
          resolve();
        }
      });
    });
  }
}

/**
 * Suíte de testes da Healthz API.
 *
 * Valida:
 * - Disponibilidade do endpoint /healthz
 * - Estrutura e conteúdo da resposta JSON
 * - Versão da aplicação
 * - Formato do timestamp
 * - Content-Type
 * - Tratamento de rotas inexistentes
 * - Tratamento de métodos HTTP não permitidos
 */
describe("Healthz API", () => {

  // TESTE 01: Valida o HTTP 200 do Health Check.
  it("deve retornar HTTP 200", async () => {
    const response = await request("/healthz");

    expect(response.status).toBe(200);
  });

  // TESTE 02: Valida o estado de saúde da aplicação.
  it("deve retornar status healthy", async () => {
    const response = await request("/healthz");

    expect(response.body.status).toBe("healthy");
    expect(response.body.application).toBe("healthz-api");
  });

  // TESTE 03: Valida a versão publicada pela aplicação.
  it("deve retornar a versão da aplicação", async () => {
    const response = await request("/healthz");

    expect(response.body.version).toBe(
      process.env.APP_VERSION || version
    );
  });

  // TESTE 04: Valida o timestamp no formato ISO 8601.
  it("deve retornar um timestamp válido", async () => {
    const response = await request("/healthz");

    expect(response.body.timestamp).toBeDefined();

    expect(
      new Date(response.body.timestamp).toISOString()
    ).toBe(response.body.timestamp);
  });

  // TESTE 05: Verifica se a API retorna JSON.
  it("deve retornar Content-Type application/json", async () => {
    const response = await request("/healthz");

    expect(response.headers.get("content-type"))
      .toContain("application/json");
  });

  // TESTE 06: Valida o tratamento de rotas inexistentes.
  it("deve retornar HTTP 404 para rota inválida", async () => {
    const response = await request("/invalid");

    expect(response.status).toBe(404);
    expect(response.body.error).toBe("Not Found");
  });

  // TESTE 07: Verifica o tratamento de métodos não suportados.
  it("deve retornar HTTP 404 para método POST", async () => {
    const response = await request("/healthz", "POST");

    expect(response.status).toBe(404);
    expect(response.body.error).toBe("Not Found");
  });
});
