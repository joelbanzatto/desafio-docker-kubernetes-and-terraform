# syntax=docker/dockerfile:1
# Build context: repo root (paths below assume ./app/web).
# API_UPSTREAM is resolved by nginx's envsubst on boot (default here is just a
# fallback; compose/Helm always override it with the real service address).

FROM nginx:1.27-alpine

ENV API_UPSTREAM=api:8080

COPY app/web/index.html app/web/app.js app/web/styles.css /usr/share/nginx/html/
COPY app/web/nginx.conf.template /etc/nginx/templates/default.conf.template

EXPOSE 8080
