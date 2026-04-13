FROM apache/gravitino:1.2.0

# PostgreSQL JDBC driver + Gravitino Iceberg AWS bundle (for S3FileIO / credential vending)
RUN set -ex && \
    wget -q -O /root/gravitino/iceberg-rest-server/libs/postgresql-42.7.3.jar \
      https://jdbc.postgresql.org/download/postgresql-42.7.3.jar && \
    wget -q -O /root/gravitino/iceberg-rest-server/libs/gravitino-iceberg-aws-bundle-1.2.0.jar \
      https://repo1.maven.org/maven2/org/apache/gravitino/gravitino-iceberg-aws-bundle/1.2.0/gravitino-iceberg-aws-bundle-1.2.0.jar

# Bake configs into the image. Gravitino's startup script (rewrite_gravitino_server_config.py)
# rewrites gravitino.conf in-place, which fails with Docker bind-mounted files ("Device or
# resource busy"). COPY avoids this by making the files part of the image layer.
COPY gravitino.conf /root/gravitino/conf/gravitino.conf
COPY gravitino-iceberg-rest-server.conf /root/gravitino/conf/gravitino-iceberg-rest-server.conf
