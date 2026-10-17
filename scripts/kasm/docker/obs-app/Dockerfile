# Workspace standalone OBS: OBS terbuka otomatis saat sesi dimulai
# (via /dockerstartup/custom_startup.sh).
# OBS_BASE_IMAGE diisi saat build (mis. custom/ubuntu-noble-obs:1.17.0).
ARG OBS_BASE_IMAGE=custom/ubuntu-noble-obs:1.17.0
FROM ${OBS_BASE_IMAGE}
USER root
COPY custom_startup.sh /dockerstartup/custom_startup.sh
RUN chmod +x /dockerstartup/custom_startup.sh
USER 1000
