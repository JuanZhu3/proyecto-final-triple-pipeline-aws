// El frontend llama a la API con rutas relativas (/api/...). En AWS el ALB
// enruta /api/* al servicio backend y todo lo demás al servicio frontend.
const API = "/api";
const $ = (id) => document.getElementById(id);

async function api(ruta, opciones = {}) {
  const res = await fetch(API + ruta, {
    headers: { "Content-Type": "application/json" },
    ...opciones,
  });
  if (res.status === 204) return null;
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body.error || `Error HTTP ${res.status}`);
  return body;
}

function mostrarError(msg) {
  $("error").textContent = msg || "";
  $("error").hidden = !msg;
}

function pintar(tareas) {
  const ul = $("lista");
  ul.replaceChildren();
  $("vacio").hidden = tareas.length > 0;
  for (const t of tareas) {
    const li = document.createElement("li");
    li.className = t.completada ? "hecha" : "";

    const label = document.createElement("label");
    const check = document.createElement("input");
    check.type = "checkbox";
    check.checked = t.completada;
    check.addEventListener("change", () => accion(() => api(`/tareas/${t.id}`, { method: "PATCH", body: JSON.stringify({ completada: check.checked }) })));
    const span = document.createElement("span");
    span.textContent = t.titulo; // textContent evita inyección de HTML
    label.append(check, span);

    const borrar = document.createElement("button");
    borrar.className = "borrar";
    borrar.title = "Eliminar";
    borrar.textContent = "✕";
    borrar.addEventListener("click", () => accion(() => api(`/tareas/${t.id}`, { method: "DELETE" })));

    li.append(label, borrar);
    ul.append(li);
  }
}

async function cargar() {
  pintar(await api("/tareas"));
}

async function accion(fn) {
  try {
    mostrarError("");
    await fn();
    await cargar();
  } catch (e) {
    mostrarError(e.message);
  }
}

async function comprobarEstado() {
  const el = $("estado-api");
  try {
    const h = await api("/health");
    el.textContent = `ok · versión ${h.version}`;
    el.className = "ok";
  } catch {
    el.textContent = "sin conexión";
    el.className = "bad";
  }
}

$("form-nueva").addEventListener("submit", (ev) => {
  ev.preventDefault();
  const campo = $("titulo");
  const titulo = campo.value.trim();
  if (!titulo) return;
  campo.value = ""; // se limpia antes de enviar para no borrar lo que se escriba mientras tanto
  accion(async () => {
    try {
      await api("/tareas", { method: "POST", body: JSON.stringify({ titulo }) });
    } catch (e) {
      if (!campo.value) campo.value = titulo; // si falla, se devuelve el texto al campo
      throw e;
    }
  });
});

fetch("version.json")
  .then((r) => r.json())
  .then((v) => ($("ver-front").textContent = `versión ${v.version}`))
  .catch(() => ($("ver-front").textContent = "versión local"));

comprobarEstado();
accion(() => Promise.resolve());
