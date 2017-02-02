FROM ruby:alpine

WORKDIR /app

COPY Gemfile /app/
RUN apk add --no-cache --virtual gem-build build-base \
    && bundle install \
    && apk del gem-build

COPY watcher.rb wizzair_api.rb /app/
CMD /app/watcher.rb
