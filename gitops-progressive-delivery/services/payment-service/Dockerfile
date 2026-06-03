FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY server.js ./
ENV NODE_ENV=production
ENV SERVICE_NAME=payment-service
ENV PORT=3002
EXPOSE 3002
USER node
CMD ["npm","start"]
