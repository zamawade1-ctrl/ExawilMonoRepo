# Multi-stage build for the MoneyExchange.Api (.NET 10) service.
# Build context is this directory (MoneyExchange.Api) — see render.yaml dockerContext.

# --- Build ---
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Restore first (cached layer) using just the project file.
COPY MoneyExchange.Api.csproj ./
RUN dotnet restore MoneyExchange.Api.csproj

# Then copy the rest and publish a trimmed, framework-dependent build.
COPY . ./
RUN dotnet publish MoneyExchange.Api.csproj -c Release -o /app/publish /p:UseAppHost=false

# --- Runtime ---
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app
COPY --from=build /app/publish ./

ENV ASPNETCORE_ENVIRONMENT=Production
# Don't watch appsettings.json for changes: the config FileSystemWatcher creates an
# inotify instance, and container hosts (Render) can hit the inotify instance limit,
# crashing startup inside WebApplication.CreateBuilder. We don't hot-reload config in
# production, so disabling the watch is both safe and the fix.
ENV DOTNET_hostBuilder__reloadConfigOnChange=false
# The app binds to $PORT at runtime (see Program.cs); Render injects it. 8080 is a
# sensible documented default for local `docker run`.
ENV PORT=8080
EXPOSE 8080

ENTRYPOINT ["dotnet", "MoneyExchange.Api.dll"]
