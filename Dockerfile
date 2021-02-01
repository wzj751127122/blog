FROM nginx:1.17.7-alpine
EXPOSE 80
EXPOSE 443
COPY public /usr/share/nginx/html