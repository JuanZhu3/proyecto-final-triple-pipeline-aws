const express = require("express");
const crypto = require("node:crypto");

/**
 * Crea la aplicación Express. El almacén es en memoria: los datos se pierden
 * al reiniciar la tarea de ECS (decisión consciente para mantener el proyecto
 * centrado en los pipelines; ver README).
 */
function createApp({ version = process.env.APP_VERSION || "local" } = {}) {
  const app = express();
  const tareas = new Map();
  const inicio = Date.now();

  app.use(express.json({ limit: "10kb" }));

  // Log mínimo de cada petición (va a CloudWatch Logs vía awslogs).
  app.use((req, res, next) => {
    const t0 = Date.now();
    res.on("finish", () => {
      console.log(JSON.stringify({ metodo: req.method, ruta: req.originalUrl, estado: res.statusCode, ms: Date.now() - t0 }));
    });
    next();
  });

  // Health check usado por el ALB, por el pipeline 3 y por el frontend.
  app.get("/api/health", (req, res) => {
    res.json({
      estado: "ok",
      servicio: "backend",
      version,
      uptimeSegundos: Math.round((Date.now() - inicio) / 1000),
      tareas: tareas.size,
    });
  });

  app.get("/api/tareas", (req, res) => {
    const lista = [...tareas.values()].sort((a, b) => a.creada.localeCompare(b.creada));
    res.json(lista);
  });

  app.post("/api/tareas", (req, res) => {
    const titulo = typeof req.body?.titulo === "string" ? req.body.titulo.trim() : "";
    if (!titulo) return res.status(400).json({ error: "El campo 'titulo' es obligatorio." });
    if (titulo.length > 200) return res.status(400).json({ error: "El título no puede superar 200 caracteres." });
    const tarea = { id: crypto.randomUUID(), titulo, completada: false, creada: new Date().toISOString() };
    tareas.set(tarea.id, tarea);
    res.status(201).json(tarea);
  });

  app.patch("/api/tareas/:id", (req, res) => {
    const tarea = tareas.get(req.params.id);
    if (!tarea) return res.status(404).json({ error: "Tarea no encontrada." });
    if (req.body?.completada !== undefined) {
      if (typeof req.body.completada !== "boolean") return res.status(400).json({ error: "'completada' debe ser booleano." });
      tarea.completada = req.body.completada;
    }
    if (req.body?.titulo !== undefined) {
      const titulo = typeof req.body.titulo === "string" ? req.body.titulo.trim() : "";
      if (!titulo || titulo.length > 200) return res.status(400).json({ error: "Título inválido." });
      tarea.titulo = titulo;
    }
    res.json(tarea);
  });

  app.delete("/api/tareas/:id", (req, res) => {
    if (!tareas.delete(req.params.id)) return res.status(404).json({ error: "Tarea no encontrada." });
    res.status(204).end();
  });

  app.use("/api", (req, res) => res.status(404).json({ error: "Ruta no encontrada." }));

  // Manejo centralizado de errores (JSON mal formado, etc.).
  app.use((err, req, res, next) => {
    if (err.type === "entity.parse.failed") return res.status(400).json({ error: "JSON inválido." });
    console.error(err);
    res.status(500).json({ error: "Error interno del servidor." });
  });

  return app;
}

module.exports = { createApp };
