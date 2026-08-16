#!/usr/bin/env python3
"""
Load the generated CSVs into the raw schema WITHOUT psql.

Streams each file with COPY ... FROM STDIN over a normal client connection,
so it needs no superuser rights and no server-side file access. Works against
a local or remote PostgreSQL from any machine that can reach the database.

Prereqs:
    pip install "psycopg[binary]>=3.1"

Usage:
    1) run sql/01_schema/01_create_schema.sql first (pgAdmin, DBeaver, anything)
    2) set the connection string below (or the DATABASE_URL env var)
    3) python load_data.py
"""
import os, sys, psycopg

CONN = os.environ.get(
    "DATABASE_URL",
    "host=localhost port=5432 dbname=retail_db user=postgres password=postgres",
)

# (table, columns in CSV order, nullable columns) -- parents before children
TABLES = [
    ("raw.stores",
     ["store_id","store_name","city","state","region","store_type","open_date"], []),
    ("raw.products",
     ["product_id","product_name","category","subcategory","unit_cost","list_price","launch_date"], []),
    ("raw.customers",
     ["customer_id","customer_name","home_state","signup_date","loyalty_tier","email_opt_in"], []),
    ("raw.orders",
     ["order_id","customer_id","store_id","channel","order_date","payment_method",
      "order_discount_rate","is_returned","return_date"], ["return_date"]),
    ("raw.order_items",
     ["order_item_id","order_id","product_id","quantity","unit_price","unit_cost","line_discount_rate"], []),
]

CSV_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data", "csv")

def load():
    with psycopg.connect(CONN, autocommit=False) as conn:
        for table, cols, _nullable in TABLES:
            path = os.path.join(CSV_DIR, table.split(".")[1] + ".csv")
            if not os.path.exists(path):
                sys.exit("Missing CSV: %s  (run data/generate_retail_data.py first)" % path)
            collist = ", ".join(cols)
            copy_sql = ("COPY %s (%s) FROM STDIN WITH (FORMAT csv, HEADER true, NULL '')"
                        % (table, collist))
            with conn.cursor() as cur, open(path, "r", newline="", encoding="utf-8") as f:
                with cur.copy(copy_sql) as cp:
                    while True:
                        chunk = f.read(1 << 20)
                        if not chunk:
                            break
                        cp.write(chunk)
                cur.execute("SELECT count(*) FROM %s" % table)
                print("  loaded %-20s %8d rows" % (table, cur.fetchone()[0]))
        conn.commit()
        with conn.cursor() as cur:
            cur.execute("ANALYZE")
    print("Done. All CSVs loaded into the raw schema.")

if __name__ == "__main__":
    load()
