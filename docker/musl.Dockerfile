ARG BASE
FROM ${BASE}
RUN apk add --no-cache build-base cmake samurai linux-headers perl bash
