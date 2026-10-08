FROM node:26 AS build

WORKDIR /wiki

COPY . .

RUN cd frontend && npm ci && npm run build

RUN cd blocks && npm ci && npm run build

RUN cd backend && npm ci --omit=dev


FROM node:alpine

WORKDIR /wiki
ENV NODE_ENV=production

RUN mkdir -p /wiki/data && chown -R node:node /wiki

COPY --chown=node:node --from=build /wiki/assets ./assets
COPY --chown=node:node --from=build /wiki/blocks/compiled ./blocks/compiled
COPY --chown=node:node --from=build /wiki/backend ./backend
COPY --chown=node:node --from=build /wiki/dev/build/config.yml ./config.yml

USER node

EXPOSE 3000

CMD ["node", "--no-experimental-webstorage", "backend"]
