// "Compilación" del frontend: copia src/ a dist/, valida que existan los
// archivos esperados y genera version.json con la versión del build.
const fs = require("node:fs");
const path = require("node:path");

const src = path.join(__dirname, "src");
const dist = path.join(__dirname, "dist");
const version = process.env.APP_VERSION || "local";

const requeridos = ["index.html", "app.js", "styles.css"];
for (const f of requeridos) {
  if (!fs.existsSync(path.join(src, f))) {
    console.error(`Falta src/${f}`);
    process.exit(1);
  }
}

fs.rmSync(dist, { recursive: true, force: true });
fs.cpSync(src, dist, { recursive: true });
fs.writeFileSync(
  path.join(dist, "version.json"),
  JSON.stringify({ version, construido: new Date().toISOString() }, null, 2)
);
console.log(`Frontend construido en dist/ (versión ${version})`);
