FROM ruby:3.4-alpine
LABEL maintainer="Matthew Iverson <matthewdiverson@gmail.com>"

RUN mkdir /etc/legionio
RUN apk update && apk add build-base postgresql-dev mysql-client mariadb-dev tzdata gcc git

COPY . ./
RUN gem install legionio tzinfo-data tzinfo --no-document --no-prerelease
CMD ruby --yjit $(which legion)
