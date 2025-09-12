# See https://aka.ms/customizecontainer to learn how to customize your debug container and how Visual Studio uses this Dockerfile to build your images for faster debugging.

# This stage is used when running from VS in fast mode (Default for Debug configuration)
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS base

RUN apt-get update -u && \
    apt-get install -y curl xz-utils && \
    rm -rf /var/lib/apt/lists/*

RUN curl -L https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-n8.0-latest-linux64-gpl-8.0.tar.xz -o /tmp/ffmpeg.tar.xz && \
    tar -xf /tmp/ffmpeg.tar.xz -C /usr/local && \
    mv /usr/local/ffmpeg-n8.0-latest-linux64-gpl-8.0/bin/* /usr/local/bin/ && \
    rm -rf /usr/local/ffmpeg-n8.0-latest-linux64-gpl-8.0 /tmp/ffmpeg.tar.xz

USER $APP_UID
WORKDIR /app

# This stage is used to build the service project
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
ARG BUILD_CONFIGURATION=Release
WORKDIR /src
COPY ["VoiceStreamer/VoiceStreamer.csproj", "VoiceStreamer/"]
RUN dotnet restore "./VoiceStreamer/VoiceStreamer.csproj"
COPY . .
WORKDIR "/src/VoiceStreamer"
RUN dotnet build "./VoiceStreamer.csproj" -c $BUILD_CONFIGURATION -o /app/build

# This stage is used to publish the service project to be copied to the final stage
FROM build AS publish
ARG BUILD_CONFIGURATION=Release
RUN dotnet publish "./VoiceStreamer.csproj" -c $BUILD_CONFIGURATION -o /app/publish /p:UseAppHost=false

# This stage is used in production or when running from VS in regular mode (Default when not using the Debug configuration)
FROM base AS final
WORKDIR /app
RUN mkdir /app/data
RUN chmod -R 755 /app/data
VOLUME /app/data
COPY --from=publish /app/publish .

ENV PATH="/usr/local/bin:${PATH}"

ENTRYPOINT ["dotnet", "VoiceStreamer.dll"]