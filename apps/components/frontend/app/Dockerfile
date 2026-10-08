# syntax=docker/dockerfile:1
FROM golang:1.22-alpine AS build
WORKDIR /src
COPY . .
RUN CGO_ENABLED=0 go build -o /out/server .

FROM scratch
COPY --from=build /out/server /server
ENV VERSION=dev
EXPOSE 8080
ENTRYPOINT ["/server"]
