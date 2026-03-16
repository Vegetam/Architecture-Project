FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY server.js ./
ENV NODE_ENV=production
ENV SERVICE_NAME=order-service
ENV PORT=3001
EXPOSE 3001
USER node
CMD ["npm","start"]
