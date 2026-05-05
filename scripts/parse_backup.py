#!/usr/bin/env python3
"""Parse PostgreSQL COPY blocks from a cluster backup into JSONL files."""

import sys
import json
from pathlib import Path

TABLES_TO_EXTRACT = {
    'public.users_user': [
        'password', 'last_login', 'is_superuser', 'uuid', 'created_at',
        'updated_at', 'username', 'is_active', 'email', 'is_staff', 'resign'
    ],
    'public.user_details_static': [
        'id', 'fcm_token', 'auth_provider', 'user_id', 'emoji', 'private'
    ],
    'public.shelf': ['id', 'name', 'order', 'user_id'],
    'public.book': [
        'id', 'isbn', 'order', 'status', 'start_date', 'finish_date',
        'rating', 'shelf_id', 'user_id', 'title', 'thumbnail'
    ],
    'public.book_memo': [
        'id', 'created_at', 'updated_at', 'content', 'book_id', 'user_id'
    ],
    'public.book_compliment': [
        'id', 'created_at', 'updated_at', 'compliment', 'book_id', 'user_id'
    ],
    'public.users_following_users': ['id', 'following_user_id', 'user_id'],
}


def parse_value(val: str) -> object:
    if val == '\\N':
        return None
    if val == 't':
        return True
    if val == 'f':
        return False
    try:
        return int(val)
    except ValueError:
        pass
    try:
        return float(val)
    except ValueError:
        pass
    return val


def parse_backup(backup_path: str, output_dir: str):
    output = Path(output_dir)
    output.mkdir(parents=True, exist_ok=True)

    with open(backup_path, 'r', encoding='utf-8') as f:
        current_table = None
        current_columns = None
        current_file = None

        for line in f:
            if line.startswith('COPY ') and ' FROM stdin' in line:
                parts = line.split('(')
                table_name = parts[0].replace('COPY ', '').strip()

                if table_name in TABLES_TO_EXTRACT:
                    cols_str = parts[1].split(')')[0]
                    current_columns = [c.strip() for c in cols_str.split(',')]
                    current_table = table_name
                    safe_name = table_name.replace('public.', '')
                    current_file = open(output / f'{safe_name}.jsonl', 'w')
                    print(f'Extracting {table_name} -> {safe_name}.jsonl')
                continue

            if current_table and line.strip() == '\\.':
                if current_file:
                    current_file.close()
                current_table = None
                current_columns = None
                current_file = None
                continue

            if current_table and current_columns and current_file:
                values = line.rstrip('\n').split('\t')
                if len(values) == len(current_columns):
                    row = {}
                    for col, val in zip(current_columns, values):
                        row[col] = parse_value(val)
                    current_file.write(json.dumps(row, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(f'Usage: {sys.argv[0]} <backup_file> [output_dir]')
        sys.exit(1)

    backup_file = sys.argv[1]
    out_dir = sys.argv[2] if len(sys.argv) > 2 else './migration_data'
    parse_backup(backup_file, out_dir)
    print('Done!')
