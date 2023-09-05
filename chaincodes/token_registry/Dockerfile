FROM golang:1.21.0-alpine3.18

WORKDIR /app
COPY . .

RUN go mod vendor
RUN go install -v ./...
RUN rm -rf ./vendor

EXPOSE 9999
CMD ["token_registry"]
