FROM dart:stable AS build

WORKDIR /app
COPY pubspec.* ./
RUN dart pub get

COPY bin ./bin
COPY lib ./lib
RUN dart compile exe bin/servidor_brilliant.dart -o /app/servidor_brilliant

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/servidor_brilliant /app/servidor_brilliant

EXPOSE 8080
ENTRYPOINT ["/app/servidor_brilliant"]
