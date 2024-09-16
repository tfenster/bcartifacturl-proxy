FROM mcr.microsoft.com/devcontainers/dotnet:1-8.0-bookworm

# also change the Dockerfile in root before publishing!
ARG BCCH_VERSION=6.0.19
WORKDIR /bcch
RUN curl -ssL "https://www.powershellgallery.com/api/v2/package/BcContainerHelper/$BCCH_VERSION" -o bcch.zip \
    && unzip bcch.zip -d temp \
    && rm bcch.zip \
    && cp temp/HelperFunctions.ps1 . \
    && cp temp/Artifacts/Get-BCArtifactUrl.ps1 . \
    && rm -r temp