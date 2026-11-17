# Etapa 1: preparar (compilar) el frontend
FROM node:22-alpine AS build
ARG APP_VERSION=local
WORKDIR /app
COPY package.json build.js ./
COPY src ./src
RUN APP_VERSION=$APP_VERSION node build.js

# Etapa 2: servir los archivos estáticos con nginx sin privilegios (puerto 8080)
FROM nginxinc/nginx-unprivileged:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/health || exit 1
