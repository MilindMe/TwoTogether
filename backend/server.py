"""Private two-person habit API. Python 3.11+, no third-party dependencies."""
import argparse
from contextlib import contextmanager
import hashlib
import json
import os
import re
import secrets
import sqlite3
import threading
import uuid
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from zoneinfo import ZoneInfo

ICONS = {'leaf.fill', 'figure.walk', 'book.fill', 'drop.fill', 'moon.fill', 'heart.fill', 'sun.max.fill', 'dumbbell.fill'}
COLORS = {'green', 'blue', 'purple', 'orange', 'pink', 'teal'}
MESSAGE = 'A little encouragement from your partner. You’ve got this!'
SCHEMA = '''
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS pair (id INTEGER PRIMARY KEY CHECK(id=1), timezone TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS people (id TEXT PRIMARY KEY, name TEXT NOT NULL, token_hash TEXT UNIQUE NOT NULL);
CREATE TRIGGER IF NOT EXISTS two_people BEFORE INSERT ON people WHEN (SELECT count(*) FROM people)>=2 BEGIN SELECT RAISE(ABORT,'Pair is full'); END;
CREATE TABLE IF NOT EXISTS habits (id TEXT PRIMARY KEY, owner TEXT NOT NULL REFERENCES people(id), name TEXT NOT NULL, icon TEXT NOT NULL, color TEXT NOT NULL, start TEXT NOT NULL, archive TEXT);
CREATE TABLE IF NOT EXISTS schedules (habit TEXT NOT NULL REFERENCES habits(id), effective TEXT NOT NULL, weekdays TEXT NOT NULL, PRIMARY KEY(habit,effective));
CREATE TABLE IF NOT EXISTS completions (habit TEXT NOT NULL REFERENCES habits(id), date TEXT NOT NULL, completed_at TEXT NOT NULL, PRIMARY KEY(habit,date));
CREATE TABLE IF NOT EXISTS receipts (person TEXT NOT NULL, operation TEXT NOT NULL, body TEXT NOT NULL, PRIMARY KEY(person,operation));
CREATE TABLE IF NOT EXISTS nudges (id TEXT PRIMARY KEY, sender TEXT NOT NULL, recipient TEXT NOT NULL, habit TEXT NOT NULL REFERENCES habits(id), date TEXT NOT NULL, created_at TEXT NOT NULL, delivery TEXT NOT NULL DEFAULT 'pending', read INTEGER NOT NULL DEFAULT 0, UNIQUE(sender,habit,date));
CREATE TABLE IF NOT EXISTS devices (person TEXT NOT NULL REFERENCES people(id), token TEXT NOT NULL, PRIMARY KEY(person,token));
'''

class APIError(Exception):
    def __init__(self, status, message):
        self.status, self.message = status, message

def require(ok, message, status=400):
    if not ok:
        raise APIError(status, message)

class Store:
    def __init__(self, path, now=None):
        self.path = str(path)
        self.now = now or (lambda: datetime.now(timezone.utc))
        with self.connect() as db:
            db.executescript(SCHEMA)

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=15)
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA foreign_keys=ON')
        try:
            with db:
                yield db
        finally:
            db.close()

    def provision(self, names, zone):
        ZoneInfo(zone)
        require(len(names) == 2 and all(n.strip() for n in names), 'Exactly two names required')
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            require(db.execute('SELECT count(*) FROM people').fetchone()[0] == 0, 'Already provisioned')
            db.execute('INSERT INTO pair VALUES(1,?)', (zone,))
            result = []
            for name in names:
                token = secrets.token_urlsafe(32)
                person = str(uuid.uuid4())
                db.execute('INSERT INTO people VALUES(?,?,?)', (person, name.strip(), hashlib.sha256(token.encode()).hexdigest()))
                result.append({'id': person, 'name': name.strip(), 'accessKey': token})
            return result

    def today(self, db):
        pair = db.execute('SELECT timezone FROM pair WHERE id=1').fetchone()
        require(pair is not None, 'Pair has not been provisioned', 503)
        return self.now().astimezone(ZoneInfo(pair[0])).date()

    def authenticate(self, db, token):
        require(bool(token), 'Enter your private account key', 401)
        row = db.execute('SELECT id FROM people WHERE token_hash=?', (hashlib.sha256(token.encode()).hexdigest(),)).fetchone()
        require(row is not None, 'Invalid account key', 401)
        return row[0]

    def snapshot(self, db, person):
        habits = []
        for row in db.execute('SELECT * FROM habits ORDER BY start,id'):
            h = dict(row)
            h['schedules'] = [{'effective': s['effective'], 'weekdays': json.loads(s['weekdays'])} for s in db.execute('SELECT * FROM schedules WHERE habit=? ORDER BY effective', (h['id'],))]
            habits.append(h)
        return {'me': person, 'timezone': db.execute('SELECT timezone FROM pair').fetchone()[0], 'today': self.today(db).isoformat(), 'people': [dict(r) for r in db.execute('SELECT id,name FROM people')], 'habits': habits, 'completions': [dict(r) for r in db.execute('SELECT habit,date,completed_at FROM completions')], 'nudges': [dict(r) for r in db.execute('SELECT * FROM nudges WHERE recipient=? OR sender=? ORDER BY created_at DESC', (person, person))]}

    def scheduled(self, db, habit, date):
        if date < habit['start'] or (habit['archive'] and date >= habit['archive']):
            return False
        row = db.execute('SELECT weekdays FROM schedules WHERE habit=? AND effective<=? ORDER BY effective DESC LIMIT 1', (habit['id'], date)).fetchone()
        return row is not None and datetime.strptime(date, '%Y-%m-%d').isoweekday() in json.loads(row[0])

    def handle(self, method, path, token, body):
        with self.connect() as db:
            # Serializes limits, mutations, and idempotency receipts across requests.
            db.execute('BEGIN IMMEDIATE')
            person = self.authenticate(db, token)
            today = self.today(db)
            stamp = self.now().isoformat()
            if method == 'GET' and path == '/v1/snapshot':
                return self.snapshot(db, person)
            require(method == 'POST', 'Unknown endpoint', 404)
            if path == '/v1/habits':
                name, icon, color, weekdays = self.appearance(body)
                habit_id = body.get('id')
                require(isinstance(habit_id, str) and len(habit_id) <= 64 and bool(habit_id), 'Habit ID required')
                old = db.execute('SELECT * FROM habits WHERE id=?', (habit_id,)).fetchone()
                if old:
                    require(old['owner'] == person, 'Only the owner can edit this habit', 403)
                    require(old['archive'] is None, 'Archived habits cannot be edited')
                    db.execute('UPDATE habits SET name=?,icon=?,color=? WHERE id=?', (name, icon, color, habit_id))
                    effective = (today + timedelta(days=1)).isoformat()
                    # Compare against tomorrow, allowing a pending edit to be reverted.
                    current = db.execute('SELECT weekdays FROM schedules WHERE habit=? AND effective<=? ORDER BY effective DESC LIMIT 1', (habit_id, effective)).fetchone()
                    if json.loads(current[0]) != weekdays:
                        db.execute('INSERT OR REPLACE INTO schedules VALUES(?,?,?)', (habit_id, effective, json.dumps(weekdays)))
                else:
                    db.execute('INSERT INTO habits VALUES(?,?,?,?,?,?,NULL)', (habit_id, person, name, icon, color, today.isoformat()))
                    db.execute('INSERT INTO schedules VALUES(?,?,?)', (habit_id, today.isoformat(), json.dumps(weekdays)))
            elif path == '/v1/archive':
                habit = self.owned(db, body.get('habit'), person)
                if habit['archive'] is None:
                    db.execute('UPDATE habits SET archive=? WHERE id=?', ((today + timedelta(days=1)).isoformat(), habit['id']))
            elif path == '/v1/completion':
                operation = body.get('operation')
                require(isinstance(operation, str) and 0 < len(operation) <= 100, 'Operation ID required')
                canonical = json.dumps(body, sort_keys=True)
                receipt = db.execute('SELECT body FROM receipts WHERE person=? AND operation=?', (person, operation)).fetchone()
                if receipt:
                    require(receipt[0] == canonical, 'Operation ID reused with different data', 409)
                    return self.snapshot(db, person)
                habit = self.owned(db, body.get('habit'), person)
                date = body.get('date')
                require(date in [today.isoformat(), (today - timedelta(days=1)).isoformat()], 'Only today and yesterday can be corrected', 422)
                require(self.scheduled(db, habit, date), 'Habit is not scheduled on this day', 422)
                require(type(body.get('completed')) is bool, 'Completed must be true or false')
                if body['completed']:
                    db.execute('INSERT OR IGNORE INTO completions VALUES(?,?,?)', (habit['id'], date, stamp))
                else:
                    db.execute('DELETE FROM completions WHERE habit=? AND date=?', (habit['id'], date))
                db.execute('INSERT INTO receipts VALUES(?,?,?)', (person, operation, canonical))
            elif path == '/v1/nudge':
                habit = db.execute('SELECT * FROM habits WHERE id=?', (body.get('habit'),)).fetchone()
                require(habit is not None, 'Habit not found', 404)
                require(habit['owner'] != person, 'Nudge your partner’s habits only', 403)
                prior = db.execute('SELECT id FROM nudges WHERE sender=? AND habit=? AND date=?', (person, habit['id'], today.isoformat())).fetchone()
                if prior:
                    return self.snapshot(db, person)  # Retrying a successful send is safe.
                require(self.scheduled(db, habit, today.isoformat()), 'Habit is not scheduled today', 422)
                require(not db.execute('SELECT 1 FROM completions WHERE habit=? AND date=?', (habit['id'], today.isoformat())).fetchone(), 'Habit is already complete', 422)
                count = db.execute('SELECT count(*) FROM nudges WHERE sender=? AND date=?', (person, today.isoformat())).fetchone()[0]
                require(count < 3, 'You have sent all three nudges for today', 429)
                db.execute('INSERT INTO nudges(id,sender,recipient,habit,date,created_at) VALUES(?,?,?,?,?,?)', (str(uuid.uuid4()), person, habit['owner'], habit['id'], today.isoformat(), stamp))
            elif path == '/v1/read':
                db.execute('UPDATE nudges SET read=1 WHERE id=? AND recipient=?', (body.get('id'), person))
            elif path == '/v1/device':
                device = body.get('token', '')
                require(isinstance(device, str) and re.fullmatch(r'[0-9a-f]{64,256}', device) is not None, 'Invalid device token')
                # A device belongs to the currently signed-in identity only.
                db.execute('DELETE FROM devices WHERE token=?', (device,))
                db.execute('INSERT INTO devices VALUES(?,?)', (person, device))
            elif path == '/v1/logout':
                db.execute('DELETE FROM devices WHERE person=? AND token=?', (person, body.get('token', '')))
            else:
                raise APIError(404, 'Unknown endpoint')
            return self.snapshot(db, person)

    def owned(self, db, habit_id, person):
        row = db.execute('SELECT * FROM habits WHERE id=?', (habit_id,)).fetchone()
        require(row is not None, 'Habit not found', 404)
        require(row['owner'] == person, 'Only the owner can change this habit', 403)
        return row

    @staticmethod
    def appearance(body):
        name, icon, color, days = (body.get(k) for k in ('name', 'icon', 'color', 'weekdays'))
        require(isinstance(name, str) and 0 < len(name.strip()) <= 60, 'Use a habit name of 1–60 characters')
        require(isinstance(icon, str) and icon in ICONS, 'Choose a preset icon')
        require(isinstance(color, str) and color in COLORS, 'Choose a preset color')
        require(isinstance(days, list) and len(days) > 0 and all(type(d) is int and 1 <= d <= 7 for d in days), 'Choose at least one weekday')
        return name.strip(), icon, color, sorted(set(days))

class Handler(BaseHTTPRequestHandler):
    server_version = 'TwoTogether/1'
    def do_GET(self):
        self.respond('GET')
    def do_POST(self):
        self.respond('POST')
    def respond(self, method):
        try:
            length = int(self.headers.get('Content-Length', '0'))
            require(0 <= length <= 16384, 'Request too large', 413)
            body = json.loads(self.rfile.read(length)) if length else {}
            require(isinstance(body, dict), 'Expected a JSON object')
            auth = self.headers.get('Authorization', '')
            token = auth[7:] if auth.startswith('Bearer ') else ''
            result = self.server.store.handle(method, self.path, token, body)
            status = 200
        except APIError as error:
            status, result = error.status, {'error': error.message}
        except (ValueError, TypeError):
            status, result = 400, {'error': 'Invalid request'}
        except Exception:
            status, result = 500, {'error': 'Server error; please retry'}
            import traceback
            traceback.print_exc()
        data = json.dumps(result).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def log_message(self, fmt, *args):
        pass  # Never log account credentials or request bodies.

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--db', default='data/habits.sqlite')
    commands = parser.add_subparsers(dest='command', required=True)
    setup = commands.add_parser('provision')
    setup.add_argument('names', nargs=2)
    setup.add_argument('--timezone', default='America/Toronto')
    serve = commands.add_parser('serve')
    serve.add_argument('--host', default='127.0.0.1')
    serve.add_argument('--port', type=int, default=8080)
    args = parser.parse_args()
    Path(args.db).parent.mkdir(parents=True, exist_ok=True)
    store = Store(args.db)
    os.chmod(args.db, 0o600)
    if args.command == 'provision':
        print(json.dumps(store.provision(args.names, args.timezone), indent=2))
    else:
        from push import delivery_loop
        threading.Thread(target=delivery_loop, args=(store,), daemon=True).start()
        server = ThreadingHTTPServer((args.host, args.port), Handler)
        server.store = store
        print(f'TwoTogether listening on {args.host}:{args.port}', flush=True)
        server.serve_forever()

if __name__ == '__main__':
    main()
