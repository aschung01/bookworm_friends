#!/usr/bin/env python3
"""Import JSONL data into Supabase, creating auth users and mapping old IDs."""

import json
import os
import sys
from pathlib import Path
from supabase import create_client, Client

SUPABASE_URL = os.environ.get('SUPABASE_URL', '')
SUPABASE_SERVICE_KEY = os.environ.get('SUPABASE_SERVICE_ROLE_KEY', '')


def load_jsonl(path: Path) -> list[dict]:
    rows = []
    with open(path, 'r') as f:
        for line in f:
            if line.strip():
                rows.append(json.loads(line))
    return rows


def main(data_dir: str):
    if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
        print('Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY env vars')
        sys.exit(1)

    supabase: Client = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
    data_path = Path(data_dir)

    # Load old data
    users = load_jsonl(data_path / 'users_user.jsonl')
    details = load_jsonl(data_path / 'user_details_static.jsonl')
    shelves_data = load_jsonl(data_path / 'shelf.jsonl')
    books_data = load_jsonl(data_path / 'book.jsonl')
    memos_data = load_jsonl(data_path / 'book_memo.jsonl')
    compliments_data = load_jsonl(data_path / 'book_compliment.jsonl')
    follows_data = load_jsonl(data_path / 'users_following_users.jsonl')

    # Build details lookup
    details_by_user = {d['user_id'].strip(): d for d in details}

    # Step 1: Create auth users, build ID mapping
    old_to_new_user: dict[str, str] = {}

    for user in users:
        if not user.get('is_active') or user.get('resign'):
            continue

        old_id = user['uuid'].strip()
        email = user['email']

        try:
            result = supabase.auth.admin.create_user({
                'email': email,
                'email_confirm': True,
            })
            new_id = result.user.id
            old_to_new_user[old_id] = new_id

            detail = details_by_user.get(old_id, {})
            supabase.table('profiles').update({
                'username': user['username'],
                'emoji': detail.get('emoji'),
                'is_private': detail.get('private', False),
            }).eq('id', new_id).execute()

            print(f'  Created user: {user["username"]} ({old_id} -> {new_id})')
        except Exception as e:
            print(f'  Error creating user {email}: {e}')

    # Step 2: Import shelves
    old_to_new_shelf: dict[int, str] = {}

    for shelf in shelves_data:
        old_user_id = shelf['user_id'].strip()
        new_user_id = old_to_new_user.get(old_user_id)
        if not new_user_id:
            continue

        result = supabase.table('shelves').insert({
            'user_id': new_user_id,
            'name': shelf['name'],
            'position': shelf['order'],
        }).execute()

        if result.data:
            old_to_new_shelf[shelf['id']] = result.data[0]['id']

    print(f'Imported {len(old_to_new_shelf)} shelves')

    # Step 3: Import books
    old_to_new_book: dict[int, str] = {}

    for book in books_data:
        old_user_id = book['user_id'].strip()
        new_user_id = old_to_new_user.get(old_user_id)
        new_shelf_id = old_to_new_shelf.get(book['shelf_id'])
        if not new_user_id or not new_shelf_id:
            continue

        result = supabase.table('books').insert({
            'user_id': new_user_id,
            'shelf_id': new_shelf_id,
            'isbn': book['isbn'],
            'title': book['title'],
            'thumbnail': book['thumbnail'],
            'status': book['status'],
            'position': book['order'],
            'rating': book.get('rating'),
            'start_date': book.get('start_date'),
            'finish_date': book.get('finish_date'),
        }).execute()

        if result.data:
            old_to_new_book[book['id']] = result.data[0]['id']

    print(f'Imported {len(old_to_new_book)} books')

    # Step 4: Import memos
    memo_count = 0
    for memo in memos_data:
        new_book_id = old_to_new_book.get(memo['book_id'])
        new_user_id = old_to_new_user.get(memo['user_id'].strip())
        if not new_book_id or not new_user_id:
            continue

        supabase.table('book_memos').insert({
            'book_id': new_book_id,
            'user_id': new_user_id,
            'content': memo['content'],
            'created_at': memo.get('created_at'),
            'updated_at': memo.get('updated_at'),
        }).execute()
        memo_count += 1

    print(f'Imported {memo_count} memos')

    # Step 5: Import compliments
    comp_count = 0
    for comp in compliments_data:
        new_book_id = old_to_new_book.get(comp['book_id'])
        new_user_id = old_to_new_user.get(comp['user_id'].strip())
        if not new_book_id or not new_user_id:
            continue

        supabase.table('book_compliments').insert({
            'book_id': new_book_id,
            'from_user_id': new_user_id,
            'compliment': comp['compliment'],
            'created_at': comp.get('created_at'),
        }).execute()
        comp_count += 1

    print(f'Imported {comp_count} compliments')

    # Step 6: Import follows
    follow_count = 0
    for follow in follows_data:
        follower_id = old_to_new_user.get(follow['user_id'].strip())
        following_id = old_to_new_user.get(follow['following_user_id'].strip())
        if not follower_id or not following_id:
            continue

        try:
            supabase.table('follows').insert({
                'follower_id': follower_id,
                'following_id': following_id,
            }).execute()
            follow_count += 1
        except Exception:
            pass

    print(f'Imported {follow_count} follows')
    print('Migration complete!')


if __name__ == '__main__':
    data_dir = sys.argv[1] if len(sys.argv) > 1 else './migration_data'
    main(data_dir)
