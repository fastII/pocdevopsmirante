
"use strict";

const http = require("node:http");
const { version } = require("../package.json");

// Porta HTTP utilizada pela aplicação.
// Pode ser sobrescrita pela variável de ambiente PORT.
const PORT = process.env.PORT || 3000;

// Versão da aplicação.
// Prioriza APP_VERSION e utiliza a versão do package.json como fallback.
const APP_VERSION = process.env.APP_VERSION || version;

/**
 * Processa as requisições HTTP da aplicação.
 *
 * Esta função fica separada da inicialização do servidor
 * para permitir testes unitários e geração de cobertura.
 *
 * @param {http.IncomingMessage} req - Requisição HTTP.
 * @param {http.ServerResponse} res - Resposta HTTP.
 */
function requestHandler(req, res) {
  // Define o formato JSON para todas as respostas.
  res.setHeader("Content-Type", "application/json");

  // Endpoint de Health Check.
  // Utilizado pelo Kubernetes para verificar a saúde da aplicação.
  if (req.url === "/healthz" && req.method === "GET") {
    res.writeHead(200);

    return res.end(
      JSON.stringify({
        status: "healthy",
        application: "healthz-api",
        version: APP_VERSION,
        timestamp: new Date().toISOString()
      })
    );
  }

  // Retorna HTTP 404 para rotas não implementadas.
  res.writeHead(404);

  return res.end(
    JSON.stringify({
      error: "Not Found"
    })
  );
}

/**
 * Cria uma instância HTTP sem iniciar a escuta.
 *
 * Isso permite utilizar portas dinâmicas nos testes,
 * evitando conflitos com o servidor da aplicação.
 */
function createServer() {
  return http.createServer(requestHandler);
}

// Inicializa o servidor apenas quando o arquivo
// é executado diretamente pelo Node.js.
//
// Quando importado pelos testes, o servidor não é iniciado.
if (require.main === module) {
  createServer().listen(PORT, "0.0.0.0", () => {
    console.log(`API listening on port ${PORT}`);
  });
}

// Exporta funções para os testes automatizados.
module.exports = {
  createServer,
  requestHandler
};
