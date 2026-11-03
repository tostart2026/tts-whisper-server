ARG BASE_IMAGE=docker.1panel.live/library/node:22-alpine
FROM ${BASE_IMAGE}

ENV NODE_ENV=production

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY server.js ./
COPY libs ./libs

EXPOSE 8883

CMD ["node", "server.js"]
