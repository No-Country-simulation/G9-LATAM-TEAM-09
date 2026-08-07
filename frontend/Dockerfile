# ==========================================
# Front-End EnergiAI — sitio estático (P-01 / P-02)
#
# Imagen no-root (nginx-unprivileged escucha en 8080, no en 80) y con
# manifiesto multi-arquitectura: corre en la VM ARM64 de OCI y en las
# máquinas x86 del equipo sin cambios.
#
# Hoy el front no tiene build. Cuando pase a Vite, se antepone una etapa:
#
#   FROM node:22-alpine AS build
#   WORKDIR /app
#   COPY package*.json ./
#   RUN npm ci
#   COPY . .
#   RUN npm run build
#
# y la etapa de abajo cambia sus COPY por:
#   COPY --from=build /app/dist /usr/share/nginx/html
#
# El resto del archivo, el compose y el workflow de CD no cambian.
# ==========================================
FROM nginxinc/nginx-unprivileged:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf

# COPY explícito en lugar de `COPY . .`: deja documentado qué se publica
# y evita que el Dockerfile, el README o archivos sueltos terminen servidos.
COPY index.html /usr/share/nginx/html/
COPY css/ /usr/share/nginx/html/css/
COPY js/ /usr/share/nginx/html/js/

EXPOSE 8080

# La imagen de Alpine no trae curl; busybox wget sí.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q --spider http://localhost:8080/ || exit 1
