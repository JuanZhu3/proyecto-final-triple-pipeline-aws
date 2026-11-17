const { createApp } = require("./app");

const port = Number(process.env.PORT || 3000);
const server = createApp().listen(port, () => {
  console.log(`Backend escuchando en el puerto ${port}`);
});

// ECS envía SIGTERM al detener una tarea: cerramos conexiones limpiamente.
for (const senal of ["SIGTERM", "SIGINT"]) {
  process.on(senal, () => {
    console.log(`${senal} recibido, cerrando servidor...`);
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(1), 10000).unref();
  });
}
