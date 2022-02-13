COPY library-scripts/powershell-debian.sh /tmp/library-scripts/
RUN apt-get update && bash /tmp/library-scripts/powershell-debian.sh