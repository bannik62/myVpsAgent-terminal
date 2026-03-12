FROM node:22-alpine

WORKDIR /app

COPY package.json ./
RUN npm install --production

COPY server.js ./

RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

EXPOSE 8000

CMD ["node", "server.js"]
