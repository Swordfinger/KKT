FROM node:24-bookworm-slim
WORKDIR /app
COPY server ./server
COPY drizzle ./drizzle
ENV HOST=0.0.0.0 PORT=4175 DATABASE_PATH=/app/data/yujian.sqlite
RUN mkdir -p /app/data && chown -R node:node /app
USER node
EXPOSE 4175
VOLUME ["/app/data"]
CMD ["node","server/local.mjs"]
