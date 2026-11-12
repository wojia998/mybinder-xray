# mybinder-xray: temporary experimental xray node on mybinder.org
# Binder/repo2docker: a Dockerfile repo must use an explicit (non-latest) tag,
# install notebook + jupyterlab + jupyterhub, copy the repo to $HOME as uid 1000,
# and exec the command Binder passes as arguments (see start.sh).
# No UUID, key or subscription link is stored in this repo: the UUID is
# generated fresh inside the live session by start.sh.
FROM jupyter/base-notebook:python-3.11

USER root

# xray runtime deps: curl to download the release, unzip to extract it,
# ca-certificates for https, procps for pgrep in start.sh
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl unzip ca-certificates procps \
    && rm -rf /var/lib/apt/lists/*

# jupyter-server-proxy: expose a local port (xray, 8080) through the public
# Binder/Jupyter URL as /proxy/<port>/...  (jupyterhub is already in the
# base image; install it explicitly so an authenticated Binder works)
RUN pip install --no-cache-dir jupyter-server-proxy jupyterhub

COPY start.sh /home/jovyan/start.sh
COPY . /home/jovyan/
RUN chown -R 1000:100 /home/jovyan/ \
    && chmod +x /home/jovyan/start.sh

USER jovyan
WORKDIR /home/jovyan

# start.sh starts xray in the background (download + fresh UUID + config)
# and then execs the Jupyter command Binder passes, e.g. jupyterhub-singleuser
ENTRYPOINT ["/home/jovyan/start.sh"]
