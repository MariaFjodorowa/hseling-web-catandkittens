FROM alpine:3.5

# Add requirements for python and pip
RUN apk add --update python3 pytest
RUN apk add --update postgresql-libs
RUN apk add --update curl

RUN mkdir -p /opt/code
WORKDIR /opt/code

ADD requirements.txt /opt/code

# Try to use local wheels. Even if not present, it will proceed
ADD ./vendor /opt/vendor
ADD ./deps /opt/deps
# Only install them if there's any
RUN if ls /opt/vendor/*.whl 1> /dev/null 2>&1; then pip3 install /opt/vendor/*.whl; fi

# Some Docker-fu. In one step install the compile packages, install the
# dependencies and then remove them. That skims the image size quite
# sensibly.
RUN apk add --no-cache --virtual .build-deps \
  python3-dev build-base linux-headers gcc postgresql-dev \
    # Installing python requirements
    && pip3 install -r requirements.txt \
    && find /usr/local \
        \( -type d -a -name test -o -name tests \) \
        -o \( -type f -a -name '*.pyc' -o -name '*.pyo' \) \
        -exec rm -rf '{}' + \
    && runDeps="$( \
        scanelf --needed --nobanner --recursive /usr/local \
                | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
                | sort -u \
                | xargs -r apk info --installed \
                | sort -u \
    )" \
    # Install uwsgi, from python
    && pip3 install uwsgi \
    && apk add --virtual .rundeps $runDeps \
    && apk del .build-deps


# Add uwsgi and nginx configuration
RUN mkdir -p /opt/server
RUN mkdir -p /opt/static
RUN apk add --update nginx
RUN mkdir -p /run/nginx
ADD ./docker/server/uwsgi.ini /opt/server
ADD ./docker/server/nginx.conf /etc/nginx/conf.d/default.conf
ADD ./docker/server/start_server.sh /opt/server

# Add code
ADD ./src/ /opt/code/

# Generate static files
RUN python3 manage.py collectstatic

EXPOSE 80
CMD ["/bin/sh", "/opt/server/start_server.sh"]
HEALTHCHECK CMD curl --fail http://localhost/smoketests/