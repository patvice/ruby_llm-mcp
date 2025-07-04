FROM oven/bun:1.2.16
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY . .
RUN bun install
EXPOSE 3005
CMD ["bun", "index.ts"]
