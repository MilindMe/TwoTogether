FROM python:3.13-slim
RUN apt-get update && apt-get install -y --no-install-recommends curl openssl tzdata ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY server.py push.py ./
RUN useradd --system --uid 10001 habits && mkdir /data && chown habits /data
USER habits
EXPOSE 8080
ENTRYPOINT ["python", "server.py", "--db", "/data/habits.sqlite"]
CMD ["serve", "--host", "0.0.0.0"]
