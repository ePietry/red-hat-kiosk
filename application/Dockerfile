# Use the Nginx unprivileged as a parent image
FROM docker.io/nginxinc/nginx-unprivileged:1.25-alpine

# Copy the static content into the container at /usr/share/nginx/html/
COPY src/local/index.html /usr/share/nginx/html/
