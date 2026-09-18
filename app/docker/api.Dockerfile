# syntax=docker/dockerfile:1
# Build context: repo root (paths below assume ./app/api).

FROM golang:1.23-alpine AS build
WORKDIR /src

COPY app/api/go.mod app/api/go.sum ./
RUN go mod download

COPY app/api/ ./
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/api .

FROM scratch
COPY --from=build /out/api /api
EXPOSE 8080
ENTRYPOINT ["/api"]
