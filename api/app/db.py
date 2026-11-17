import os
from contextlib import contextmanager
import psycopg

PRIMARY = os.environ.get("DB_PRIMARY_HOST", "db-primary")
REPLICA = os.environ.get("DB_REPLICA_HOST", "db-replica")


@contextmanager
def conn(host):
    connection = psycopg.connect(
        host=host,
        dbname=os.environ.get("DB_NAME", "appdb"),
        user=os.environ.get("DB_USER", "postgres"),
        password=os.environ.get("DB_PASSWORD", ""),
        connect_timeout=5,
    )
    try:
        with connection:
            yield connection
    finally:
        connection.close()
