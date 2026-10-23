"""Exercise HTTP parsing and APNs behavior without external services."""
import base64
import io
import json
import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from server import Handler, Store
from push import deliver_pending, provider_token

class RequestSocket:
    def __init__(self, raw):
        self.input = io.BytesIO(raw)
        self.output = bytearray()
    def makefile(self, *args): return self.input
    def sendall(self, data): self.output.extend(data)

class TransportTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.store = Store(Path(self.tmp.name) / 'db.sqlite')
        self.users = self.store.provision(['Alex', 'Sam'], 'America/Toronto')
    def tearDown(self): self.tmp.cleanup()
    def request(self, method, path, body=None, token=None, raw_body=None):
        data = raw_body if raw_body is not None else json.dumps(body or {}).encode()
        headers = f'{method} {path} HTTP/1.0\r\nContent-Length: {len(data)}\r\n'
        if token: headers += f'Authorization: Bearer {token}\r\n'
        request = RequestSocket(headers.encode() + b'\r\n' + data)
        Handler(request, ('127.0.0.1', 1234), SimpleNamespace(store=self.store))
        head, response = bytes(request.output).split(b'\r\n\r\n', 1)
        return int(head.split()[1]), json.loads(response)
    def test_http_auth_and_json_errors(self):
        self.assertEqual(self.request('GET', '/v1/snapshot')[0], 401)
        self.assertEqual(self.request('POST', '/v1/habits', token=self.users[0]['accessKey'], raw_body=b'{bad')[0], 400)
        self.assertEqual(self.request('POST', '/v1/habits', token=self.users[0]['accessKey'], raw_body=b'[]')[0], 400)
        self.assertEqual(self.request('GET', '/v1/unknown', token=self.users[0]['accessKey'])[0], 404)
    def test_http_two_accounts_create_and_read(self):
        code, data = self.request('POST', '/v1/habits', dict(id='walk', name='Walk', icon='leaf.fill', color='green', weekdays=[1,2,3,4,5,6,7]), self.users[0]['accessKey'])
        self.assertEqual(code, 200)
        code, other = self.request('GET', '/v1/snapshot', token=self.users[1]['accessKey'])
        self.assertEqual(code, 200)
        self.assertEqual(other['habits'], data['habits'])
        self.assertNotEqual(other['me'], data['me'])
    def create_push(self):
        self.store.handle('POST', '/v1/habits', self.users[1]['accessKey'], dict(id='walk', name='Walk', icon='leaf.fill', color='green', weekdays=[1,2,3,4,5,6,7]))
        self.store.handle('POST', '/v1/device', self.users[1]['accessKey'], {'token': 'a' * 64})
        self.store.handle('POST', '/v1/nudge', self.users[0]['accessKey'], {'habit': 'walk'})
    def test_provider_signature_is_jwt_raw_es256(self):
        r = b'\0' + b'\x88' * 32
        s = b'\x77' * 32
        der = bytes([0x30, 4 + len(r) + len(s), 0x02, len(r)]) + r + bytes([0x02, len(s)]) + s
        with patch.dict(os.environ, {'APNS_KEY_ID': 'key', 'APNS_TEAM_ID': 'team', 'APNS_KEY_PATH': '/fake.p8'}), patch('push.subprocess.run', return_value=SimpleNamespace(stdout=der)):
            token = provider_token()
        signature = base64.urlsafe_b64decode(token.split('.')[2] + '==')
        self.assertEqual(signature, b'\x88' * 32 + s)
    def test_push_retries_transient_failure_and_preserves_inbox(self):
        self.create_push()
        env = dict(APNS_KEY_ID='key', APNS_TEAM_ID='team', APNS_KEY_PATH='/fake.p8', APNS_TOPIC='com.example.habits')
        with patch.dict(os.environ, env), patch('push.provider_token', return_value='signed.jwt'), patch('push.subprocess.run', return_value=SimpleNamespace(stdout=b'{}\n503')) as curl:
            deliver_pending(self.store)
            deliver_pending(self.store)  # Backoff prevents an immediate second attempt.
            self.assertEqual(curl.call_count, 1)
        with self.store.connect() as db:
            self.assertEqual(db.execute('SELECT state FROM push_jobs').fetchone()[0], 'pending')
            db.execute('UPDATE push_jobs SET next_try=0')
        with patch.dict(os.environ, env), patch('push.provider_token', return_value='signed.jwt'), patch('push.subprocess.run', return_value=SimpleNamespace(stdout=b'\n200')):
            deliver_pending(self.store)
        with self.store.connect() as db:
            self.assertEqual(db.execute('SELECT delivery FROM nudges').fetchone()[0], 'sent')
            self.assertEqual(db.execute('SELECT read FROM nudges').fetchone()[0], 0)
    def test_expired_push_device_is_removed_but_nudge_remains(self):
        self.create_push()
        env = dict(APNS_KEY_ID='key', APNS_TEAM_ID='team', APNS_KEY_PATH='/fake.p8', APNS_TOPIC='com.example.habits')
        with patch.dict(os.environ, env), patch('push.provider_token', return_value='signed.jwt'), patch('push.subprocess.run', return_value=SimpleNamespace(stdout=b'{}\n410')):
            deliver_pending(self.store)
        with self.store.connect() as db:
            self.assertEqual(db.execute('SELECT count(*) FROM devices').fetchone()[0], 0)
            self.assertEqual(db.execute('SELECT delivery FROM nudges').fetchone()[0], 'in_app')

if __name__ == '__main__': unittest.main()
