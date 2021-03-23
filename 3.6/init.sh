#!/bin/bash -ex

DATA_DIR=/app/src/data
OSMFILE=${DATA_DIR}/data.osm.pbf

if [ "$PBF_URL" = "" ]; then
  echo "You need to specify the environment variable PBF_URL"
  echo "docker run -e PBF_URL=http://download.geofabrik.de/europe/monaco-latest.osm.pbf ..."
  exit 1
fi;

if [ "$REPLICATION_URL" = "" ]; then
  echo "You need to specify the environment variable REPLICATION_URL"
  echo "docker run -e REPLICATION_URL=http://download.geofabrik.de/europe/monaco-updates/ ..."
  exit 1
else
  sed -i "s|__REPLICATION_URL__|$REPLICATION_URL|g" /app/src/build/settings/local.php
fi;


if [ "$IMPORT_WIKIPEDIA" = "true" ]; then
  echo "Downloading Wikipedia importance dump"
  curl https://www.nominatim.org/data/wikimedia-importance.sql.gz -o ${DATA_DIR}/wikimedia-importance.sql.gz
else
  echo "Skipping optional Wikipedia importance import"
fi;

if [ "$IMPORT_GB_POSTCODES" = "true" ]; then
  curl http://www.nominatim.org/data/gb_postcode_data.sql.gz -o ${DATA_DIR}/gb_postcode_data.sql.gz
else \
  echo "Skipping optional GB postcode import"
fi;

if [ "$IMPORT_US_POSTCODES" = "true" ]; then
  curl http://www.nominatim.org/data/us_postcode_data.sql.gz -o ${DATA_DIR}/us_postcode_data.sql.gz
else
  echo "Skipping optional US postcode import"
fi;


echo Downloading OSM extract from "$PBF_URL"
curl -L "$PBF_URL" --create-dirs -o $OSMFILE

# Update postgres config to improve import performance
sed -i "s/fsync = on/fsync = off/g" /etc/postgresql/12/main/postgresql.conf
sed -i "s/full_page_writes = on/full_page_writes = off/g" /etc/postgresql/12/main/postgresql.conf

sudo service postgresql start && \
sudo -u postgres psql postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='nominatim'" | grep -q 1 || sudo -u postgres createuser -s nominatim && \
sudo -u postgres psql postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='www-data'" | grep -q 1 || sudo -u postgres createuser -SDR www-data && \

sudo -u postgres psql postgres -tAc "ALTER USER nominatim WITH ENCRYPTED PASSWORD '$NOMINATIM_PASSWORD'" && \
sudo -u postgres psql postgres -tAc "ALTER USER \"www-data\" WITH ENCRYPTED PASSWORD '${NOMINATIM_PASSWORD}'" && \

sudo -u postgres psql postgres -c "DROP DATABASE IF EXISTS nominatim" && \
chown -R nominatim:nominatim ./src && \
sudo -u nominatim ./src/build/utils/setup.php --osm-file $OSMFILE --all --threads $THREADS && \
sudo -u nominatim ./src/build/utils/check_import_finished.php && \
sudo -u nominatim ./src/build/utils/update.php --init-updates

sudo service postgresql stop

sed -i "s/fsync = off/fsync = on/g" /etc/postgresql/12/main/postgresql.conf
sed -i "s/full_page_writes = off/full_page_writes = on/g" /etc/postgresql/12/main/postgresql.conf

echo "Deleting downloaded dumps in ${DATA_DIR}"
rm ${DATA_DIR}/*sql.gz ${OSMFILE}
