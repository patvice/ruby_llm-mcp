FROM ruby:3.4
RUN apt-get update && \
    apt-get install -y curl && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY . .
RUN bundle install
ENV BIND=tcp://0.0.0.0:3006
ENV DOCKER=true
EXPOSE 3006
CMD ["ruby", "lib/app.rb"]
