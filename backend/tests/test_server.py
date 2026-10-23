import concurrent.futures
import json
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from server import APIError, Store
from push import deliver_pending

class HabitsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.now = datetime(2026, 10, 22, 16, tzinfo=timezone.utc)
        self.db = str(Path(self.tmp.name) / 'test.sqlite')
        self.store = Store(self.db, lambda: self.now)
        self.users = self.store.provision(['Alex', 'Sam'], 'America/Toronto')
        self.a, self.b = [x['accessKey'] for x in self.users]
    def tearDown(self):
        self.tmp.cleanup()
    def call(self, endpoint, body, token=None):
        return self.store.handle('POST', '/v1/' + endpoint, token or self.a, body)
    def snap(self, token=None):
        return self.store.handle('GET', '/v1/snapshot', token or self.a, {})
    def habit(self, ident='walk', token=None, days=None):
        return self.call('habits', dict(id=ident, name='Go for a walk', icon='figure.walk', color='green', weekdays=days or list(range(1, 8))), token)
    def complete(self, operation='op', value=True, date='2026-10-22', token=None, habit='walk'):
        return self.call('completion', dict(operation=operation, habit=habit, date=date, completed=value), token)
    def assertStatus(self, status, fn):
        with self.assertRaises(APIError) as error:
            fn()
        self.assertEqual(error.exception.status, status)
    def test_pair_is_fixed_and_auth_is_private(self):
        self.assertStatus(401, lambda: self.snap('unapproved'))
        self.assertStatus(400, lambda: self.store.provision(['Third', 'Fourth'], 'America/Toronto'))
        with self.store.connect() as db:
            self.assertNotIn(self.a, str([tuple(r) for r in db.execute('SELECT * FROM people')]))
        self.assertEqual(len(self.snap()['people']), 2)
    def test_shared_reads_and_owner_only_writes(self):
        self.habit()
        self.assertEqual(len(self.snap(self.b)['habits']), 1)
        self.assertStatus(403, lambda: self.habit(token=self.b))
        self.assertStatus(403, lambda: self.complete(token=self.b))
        self.assertStatus(403, lambda: self.call('archive', {'habit': 'walk'}, self.b))
    def test_completion_retries_and_undo(self):
        self.habit()
        self.complete()
        self.complete()
        self.assertEqual(len(self.snap()['completions']), 1)
        self.assertStatus(409, lambda: self.complete(value=False))
        self.complete('undo', False)
        self.complete()  # Retry must not resurrect an earlier write.
        self.assertEqual(self.snap()['completions'], [])
    def test_concurrent_completion_requests_are_unique(self):
        self.habit()
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(lambda i: self.complete(str(i)), range(20)))
        self.assertEqual(len(self.snap()['completions']), 1)
    def test_only_scheduled_today_and_yesterday_can_be_corrected(self):
        self.habit(days=[4])
        self.complete()
        self.assertStatus(422, lambda: self.complete('old', date='2026-10-20'))
        self.assertStatus(422, lambda: self.complete('future', date='2026-10-23'))
        self.assertStatus(422, lambda: self.complete('before-start', date='2026-10-21'))
        self.now = datetime(2026, 10, 23, 16, tzinfo=timezone.utc)
        self.complete('yesterday', False)
        self.assertStatus(422, lambda: self.complete('off-day', date='2026-10-23'))
    def test_schedule_history_and_pending_schedule_revert(self):
        self.habit(days=[4])
        self.habit(days=[5])
        h = self.snap()['habits'][0]
        self.assertEqual(h['schedules'], [{'effective': '2026-10-22', 'weekdays': [4]}, {'effective': '2026-10-23', 'weekdays': [5]}])
        with self.store.connect() as db:
            row = db.execute('SELECT * FROM habits').fetchone()
            self.assertTrue(self.store.scheduled(db, row, '2026-10-22'))
            self.assertTrue(self.store.scheduled(db, row, '2026-10-23'))
        self.habit(days=[4])
        self.assertEqual(self.snap()['habits'][0]['schedules'][-1]['weekdays'], [4])
    def test_archive_preserves_today_and_history(self):
        self.habit()
        self.complete()
        self.call('archive', {'habit': 'walk'})
        self.assertEqual(self.snap()['habits'][0]['archive'], '2026-10-23')
        self.complete('undo', False)
        self.now = datetime(2026, 10, 23, 16, tzinfo=timezone.utc)
        self.assertStatus(422, lambda: self.complete('archived', date='2026-10-23'))
        self.assertStatus(400, lambda: self.habit())
    def test_pair_timezone_and_dst(self):
        for stamp, day in [('2026-10-23T03:59:59+00:00', '2026-10-22'), ('2026-10-23T04:00:00+00:00', '2026-10-23'), ('2026-11-01T05:30:00+00:00', '2026-11-01'), ('2026-11-01T06:30:00+00:00', '2026-11-01')]:
            self.now = datetime.fromisoformat(stamp)
            self.assertEqual(self.snap()['today'], day)
    def test_nudge_limits_inbox_and_read_ownership(self):
        for i in range(4): self.habit(str(i), self.b)
        for i in range(3): self.call('nudge', {'habit': str(i)})
        self.call('nudge', {'habit': '0'})
        self.assertStatus(429, lambda: self.call('nudge', {'habit': '3'}))
        inbox = self.snap(self.b)['nudges']
        self.assertEqual(len(inbox), 3)
        n = inbox[0]['id']
        self.call('read', {'id': n})
        self.assertEqual(next(x for x in self.snap(self.b)['nudges'] if x['id'] == n)['read'], 0)
        self.call('read', {'id': n}, self.b)
        self.assertEqual(next(x for x in self.snap(self.b)['nudges'] if x['id'] == n)['read'], 1)
        deliver_pending(self.store)
        self.assertTrue(all(x['delivery'] == 'in_app' for x in self.snap(self.b)['nudges']))
    def test_nudge_concurrency_limit(self):
        for i in range(8): self.habit(str(i), self.b)
        def send(i):
            try: self.call('nudge', {'habit': str(i)})
            except APIError as error: self.assertEqual(error.status, 429)
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool: list(pool.map(send, range(8)))
        self.assertEqual(len(self.snap()['nudges']), 3)
    def test_completed_and_unscheduled_habits_cannot_be_nudged(self):
        self.habit()
        self.assertStatus(403, lambda: self.call('nudge', {'habit': 'walk'}))
        self.complete()
        self.assertStatus(422, lambda: self.call('nudge', {'habit': 'walk'}, self.b))
        self.habit('rest', days=[1])
        self.assertStatus(422, lambda: self.call('nudge', {'habit': 'rest'}, self.b))
    def test_retry_survives_server_restart_and_new_day(self):
        self.habit()
        self.complete()
        self.store = Store(self.db, lambda: self.now)
        self.now = datetime(2026, 10, 26, 16, tzinfo=timezone.utc)
        self.complete()  # Already accepted op can retry after correction window.
        self.assertEqual(len(self.snap()['completions']), 1)
    def test_device_registration_transfers_and_logout_removes(self):
        token = 'a' * 64
        self.call('device', {'token': token})
        self.call('device', {'token': token}, self.b)
        with self.store.connect() as db:
            self.assertEqual(db.execute('SELECT person FROM devices').fetchone()[0], self.users[1]['id'])
        self.call('logout', {'token': token}, self.b)
        with self.store.connect() as db: self.assertEqual(db.execute('SELECT count(*) FROM devices').fetchone()[0], 0)

if __name__ == '__main__': unittest.main()
