#!/usr/bin/env python3
"""One-time loss-avoiding data migration. Schema must be created with EF migrations.

Use: python tools/migrate_sqlite_to_postgres.py --sqlite /path/to/ScholarshipHive.dev.db --inventory
     python tools/migrate_sqlite_to_postgres.py --sqlite /path/to/ScholarshipHive.dev.db --execute
Requires: python -m pip install "psycopg[binary]"
PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD configure target via environment.
"""
import argparse
import datetime as dt
import os
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path


def source_connection(path):
    # Mode=ro prevents modifying the legacy source; SQLite automatically reads WAL
    # if the matching -wal/-shm sidecars are present next to the database.
    uri = Path(path).absolute().as_uri().replace('file:///', 'file:///') + '?mode=ro'
    conn = sqlite3.connect(uri, uri=True)
    conn.row_factory = sqlite3.Row
    return conn


def sources(src):
    names = [r['name'] for r in src.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")]
    return {n: src.execute('SELECT count(*) FROM "' + n.replace('"', '""') + '"').fetchone()[0] for n in names}


def convert(value, pgtype, table, col):
    if value is None:
        return None
    if pgtype == 'boolean':
        if isinstance(value, str):
            if value.lower() not in ('0', '1', 'true', 'false'):
                raise ValueError(f'{table}.{col}: unrecognized boolean value')
            return value.lower() in ('1', 'true')
        return bool(value)
    if pgtype in ('timestamp with time zone', 'timestamp without time zone'):
        if isinstance(value, str):
            v = value.strip().replace(' ', 'T', 1)
            if v.endswith('Z'): v = v[:-1] + '+00:00'
            stamp = dt.datetime.fromisoformat(v)
        else:
            stamp = value
        if pgtype == 'timestamp with time zone':
            # EF SQLite persisted server-generated UTC timestamps as naive ISO
            # strings. This mapping is intentionally UTC; review any manually
            # inserted legacy timestamps for different timezones before import.
            return stamp.replace(tzinfo=dt.timezone.utc) if stamp.tzinfo is None else stamp.astimezone(dt.timezone.utc)
        return stamp.replace(tzinfo=None)
    if pgtype == 'date':
        return dt.date.fromisoformat(value[:10]) if isinstance(value, str) else value
    if pgtype.startswith('time '):
        return dt.time.fromisoformat(value) if isinstance(value, str) else value
    if pgtype == 'bytea':
        return bytes(value)
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sqlite', required=True)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--inventory', action='store_true')
    group.add_argument('--execute', action='store_true')
    args = parser.parse_args()
    if not Path(args.sqlite).is_file(): parser.error('SQLite source not found')
    src = source_connection(args.sqlite)
    inventory = sources(src)
    for table, count in sorted(inventory.items()): print(f'{table:30s} {count:>9} row(s)')
    if args.inventory:
        print('Inventory only. No PostgreSQL writes performed.')
        return

    missing = [e for e in ('PGHOST', 'PGDATABASE', 'PGUSER') if not os.environ.get(e)]
    if missing: parser.error('Missing environment: ' + ', '.join(missing))
    try:
        import psycopg
        from psycopg import sql
    except ImportError:
        parser.error('Install driver: python -m pip install "psycopg[binary]"')

    # All inserts, table count checks and sequence resets are ONE transaction.
    # Any error rolls back the entire import (old SQLite remains untouched).
    with psycopg.connect() as pg:
        with pg.transaction():
            with pg.cursor() as cur:
                cur.execute("SELECT pg_advisory_xact_lock(hashtext('scholarshiphive_migration'))")
                cur.execute("""SELECT table_name, column_name, data_type, is_nullable, column_default,
                                      is_identity, ordinal_position
                               FROM information_schema.columns
                               WHERE table_schema='public' ORDER BY table_name, ordinal_position""")
                target = defaultdict(list)
                for table, col, typ, nullable, default, identity, pos in cur.fetchall():
                    if table != '__EFMigrationsHistory':
                        target[table].append((col, typ, nullable, default, identity))
                if 'Users' not in target or 'Attendances' not in target:
                    raise RuntimeError('Target schema missing. Run dotnet ef database update FIRST.')
                cur.execute('SELECT "MigrationId" FROM "__EFMigrationsHistory" LIMIT 1')
                if not cur.fetchone():
                    raise RuntimeError('EF migrations not present; target schema must be migrated first.')
                for table in sorted(target):
                    cur.execute(sql.SQL('SELECT count(*) FROM {}').format(sql.Identifier('public',table)))
                    if cur.fetchone()[0]:
                        raise RuntimeError(f'Target table {table} is NOT EMPTY. Import aborted to prevent duplicate/mixed data. Use a NEW empty migrated PostgreSQL database.')
                nonempty_missing = [(t,n) for t,n in inventory.items() if n and t not in target]
                if nonempty_missing:
                    raise RuntimeError('Source has tables missing in PostgreSQL: ' + str(nonempty_missing))

                # Order tables with parents first by foreign-key dependencies.
                cur.execute('''SELECT child.relname, parent.relname
                               FROM pg_constraint c
                               JOIN pg_class child ON child.oid=c.conrelid
                               JOIN pg_class parent ON parent.oid=c.confrelid
                               JOIN pg_namespace ns ON child.relnamespace=ns.oid
                               WHERE c.contype='f' AND ns.nspname='public' ''')
                dependencies = defaultdict(set)
                for child, parent in cur.fetchall():
                    if child != parent and child in target and parent in target:
                        dependencies[child].add(parent)
                remaining = set(target); ordered=[]
                while remaining:
                    ready = sorted(t for t in remaining if not (dependencies[t] & remaining))
                    if not ready:
                        raise RuntimeError('Cyclic FK references detected; refusing unsafe import')
                    ordered += ready
                    remaining.difference_update(ready)

                for table in ordered:
                    n = inventory.get(table, 0)
                    if not n: continue
                    src_cols = [row['name'] for row in src.execute('PRAGMA table_info("' + table.replace('"', '""') + '")')]
                    pg_cols = {col: (typ, nullable, default, identity) for col, typ, nullable, default, identity in target[table]}
                    selected = [c for c in src_cols if c in pg_cols]
                    missing_required = [c for c, typ, null, default, identity in target[table]
                                        if c not in src_cols and null=='NO' and default is None and identity=='NO']
                    if missing_required:
                        raise RuntimeError(f'{table}: missing required columns in legacy data: {missing_required}')
                    q = sql.SQL('INSERT INTO {} ({}) VALUES ({})').format(
                        sql.Identifier('public', table),
                        sql.SQL(', ').join(sql.Identifier(c) for c in selected),
                        sql.SQL(', ').join(sql.Placeholder() for _ in selected))
                    select_sql = 'SELECT ' + ', '.join('"'+c.replace('"','""')+'"' for c in selected) + ' FROM "'+table.replace('"','""')+'"'
                    reader = src.execute(select_sql)
                    inserted = 0
                    while True:
                        chunk = reader.fetchmany(200)
                        if not chunk: break
                        rows = [tuple(convert(row[c], pg_cols[c][0], table, c) for c in selected) for row in chunk]
                        cur.executemany(q, rows)
                        inserted += len(rows)
                    if inserted != n: raise RuntimeError(f'{table}: row count mismatch')
                    print(f'Copied {table}: {inserted}')
                # Keep future identity inserts above the largest imported ID.
                for table in target:
                    for col, _, _, _, identity in target[table]:
                        if identity == 'YES':
                            cur.execute('SELECT pg_get_serial_sequence(%s,%s)', (f'public."{table}"', col))
                            seq = cur.fetchone()[0]
                            if seq:
                                cur.execute(sql.SQL('SELECT COALESCE(MAX({}),0) FROM {}').format(sql.Identifier(col),sql.Identifier('public',table)))
                                max_id=cur.fetchone()[0]
                                # setval is not transactional in PostgreSQL. This can only
                                # advance a sequence, never overwrite business rows.
                                cur.execute('SELECT setval(%s,%s,%s)', (seq, max(max_id,1), max_id>0))
                for table,n in inventory.items():
                    if table not in target: continue
                    cur.execute(sql.SQL('SELECT count(*) FROM {}').format(sql.Identifier('public',table)))
                    if cur.fetchone()[0]!=n:
                        raise RuntimeError('Post-import verification failed for '+table)
    print('SUCCESS: imported rows and verified counts. Legacy SQLite remains unchanged.')
    print('Now start backend: dotnet run. Review users, attendance, networks and audit logs in pgAdmin.')

if __name__=='__main__':
    try: main()
    except Exception as exc:
        print('MIGRATION FAILED: '+str(exc), file=sys.stderr)
        sys.exit(1)
