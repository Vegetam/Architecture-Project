FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY server.js ./
ENV NODE_ENV=production
ENV SERVICE_NAME=saga-orchestrator
ENV PORT=3000
EXPOSE 3000
USER node
CMD ["npm","start"]
