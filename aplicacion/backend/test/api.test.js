const test = require("node:test");
const assert = require("node:assert");
const { createApp } = require("../src/app");

async function conServidor(fn) {
  const server = createApp({ version: "test" }).listen(0);
  await new Promise((r) => server.once("listening", r));
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    await fn(base);
  } finally {
    server.close();
  }
}

test("GET /api/health responde ok", () =>
  conServidor(async (base) => {
    const res = await fetch(`${base}/api/health`);
    assert.strictEqual(res.status, 200);
    const body = await res.json();
    assert.strictEqual(body.estado, "ok");
    assert.strictEqual(body.version, "test");
  }));

test("CRUD de tareas", () =>
  conServidor(async (base) => {
    const json = { "Content-Type": "application/json" };

    let res = await fetch(`${base}/api/tareas`, { method: "POST", headers: json, body: JSON.stringify({ titulo: "  Preparar demo  " }) });
    assert.strictEqual(res.status, 201);
    const tarea = await res.json();
    assert.strictEqual(tarea.titulo, "Preparar demo");
    assert.strictEqual(tarea.completada, false);

    res = await fetch(`${base}/api/tareas`);
    assert.deepStrictEqual((await res.json()).map((t) => t.id), [tarea.id]);

    res = await fetch(`${base}/api/tareas/${tarea.id}`, { method: "PATCH", headers: json, body: JSON.stringify({ completada: true }) });
    assert.strictEqual((await res.json()).completada, true);

    res = await fetch(`${base}/api/tareas/${tarea.id}`, { method: "DELETE" });
    assert.strictEqual(res.status, 204);

    res = await fetch(`${base}/api/tareas/${tarea.id}`, { method: "DELETE" });
    assert.strictEqual(res.status, 404);
  }));

test("Validación de entrada", () =>
  conServidor(async (base) => {
    const json = { "Content-Type": "application/json" };
    let res = await fetch(`${base}/api/tareas`, { method: "POST", headers: json, body: JSON.stringify({ titulo: "" }) });
    assert.strictEqual(res.status, 400);

    res = await fetch(`${base}/api/tareas`, { method: "POST", headers: json, body: "{malo" });
    assert.strictEqual(res.status, 400);

    res = await fetch(`${base}/api/no-existe`);
    assert.strictEqual(res.status, 404);
  }));
