
const http = require("node:http");
const { version } = require("../package.json");

const PORT = process.env.PORT || 3000;
const APP_VERSION = process.env.APP_VERSION || version;

http.createServer((req, res) => {
  res.setHeader("Content-Type", "application/json");

  if (req.url === "/healthz" && req.method === "GET") {
    res.writeHead(200);
    return res.end(JSON.stringify({
      status: "healthy",
      application: "healthz-api",
      version: APP_VERSION,
      timestamp: new Date().toISOString()
    }));
  }

  res.writeHead(404);
  res.end(JSON.stringify({ error: "Not Found" }));
}).listen(PORT, "0.0.0.0", () => {
  console.log(`API listening on port ${PORT}`);
});
