"""APNs worker. Inbox persistence is independent of push permission/delivery."""
import base64
import json
import os
import subprocess
import time


def b64(value):
    return base64.urlsafe_b64encode(value).rstrip(b'=').decode()


def provider_token():
    header = b64(json.dumps({'alg': 'ES256', 'kid': os.environ['APNS_KEY_ID']}).encode())
    claims = b64(json.dumps({'iss': os.environ['APNS_TEAM_ID'], 'iat': int(time.time())}).encode())
    signing = f'{header}.{claims}'
    der = subprocess.run(['openssl', 'dgst', '-sha256', '-sign', os.environ['APNS_KEY_PATH']], input=signing.encode(), capture_output=True, check=True).stdout
    # OpenSSL emits an ASN.1 SEQUENCE of two INTEGERs; JWT needs raw r || s.
    if len(der) < 8 or der[0] != 0x30 or der[2] != 0x02:
        raise ValueError('Unexpected ES256 signature')
    size_r = der[3]
    r = der[4:4 + size_r]
    at = 4 + size_r
    if der[at] != 0x02:
        raise ValueError('Unexpected ES256 signature')
    s = der[at + 2:at + 2 + der[at + 1]]
    signature = r.lstrip(b'\0').rjust(32, b'\0') + s.lstrip(b'\0').rjust(32, b'\0')
    return f'{signing}.{b64(signature)}'


def deliver_pending(store):
    configured = all(os.getenv(k) for k in ('APNS_KEY_ID', 'APNS_TEAM_ID', 'APNS_KEY_PATH', 'APNS_TOPIC'))
    with store.connect() as db:
        db.execute('''CREATE TABLE IF NOT EXISTS push_jobs (
          nudge TEXT NOT NULL, token TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'pending',
          attempts INTEGER NOT NULL DEFAULT 0, next_try REAL NOT NULL DEFAULT 0,
          PRIMARY KEY(nudge,token))''')
        for nudge in db.execute("SELECT * FROM nudges WHERE delivery='pending'").fetchall():
            tokens = db.execute('SELECT token FROM devices WHERE person=?', (nudge['recipient'],)).fetchall()
            if not configured or not tokens:
                db.execute("UPDATE nudges SET delivery='in_app' WHERE id=?", (nudge['id'],))
            else:
                for token in tokens:
                    db.execute('INSERT OR IGNORE INTO push_jobs(nudge,token) VALUES(?,?)', (nudge['id'], token[0]))
                db.execute("UPDATE nudges SET delivery='queued' WHERE id=?", (nudge['id'],))
        jobs = db.execute("SELECT j.*,n.habit,n.date,p.name AS sender,h.name AS habit_name FROM push_jobs j JOIN nudges n ON n.id=j.nudge JOIN people p ON p.id=n.sender JOIN habits h ON h.id=n.habit WHERE j.state='pending' AND j.next_try<=?", (time.time(),)).fetchall()
    jwt = provider_token() if jobs else None
    host = 'api.sandbox.push.apple.com' if os.getenv('APNS_SANDBOX', 'true').lower() == 'true' else 'api.push.apple.com'
    for job in jobs:
        payload = {'aps': {'alert': {'body': f'{job["sender"]} nudged you about {job["habit_name"]}.'}, 'sound': 'default'}, 'habit': job['habit'], 'nudge': job['nudge']}
        # Credentials are passed through stdin config, not command arguments.
        config = f'header = "authorization: bearer {jwt}"\n'
        result = subprocess.run(['curl', '--config', '-', '--http2', '--silent', '--show-error', '--max-time', '15', '--request', 'POST', '--header', f'apns-topic: {os.environ["APNS_TOPIC"]}', '--header', 'apns-push-type: alert', '--header', 'apns-priority: 10', '--header', f'apns-id: {job["nudge"]}', '--header', f'apns-collapse-id: {job["nudge"]}', '--header', f'apns-expiration: {int(time.time()) + 3600}', '--data-binary', json.dumps(payload), '--write-out', '\n%{http_code}', f'https://{host}/3/device/{job["token"]}'], input=config.encode(), capture_output=True)
        status = result.stdout.decode(errors='replace').rsplit('\n', 1)[-1]
        attempts = job['attempts'] + 1
        state = 'sent' if status == '200' else ('failed' if status in ('400', '403', '404', '405', '410', '413') or attempts >= 8 else 'pending')
        with store.connect() as db:
            db.execute('UPDATE push_jobs SET state=?,attempts=?,next_try=? WHERE nudge=? AND token=?', (state, attempts, time.time() + min(3600, 2 ** attempts * 5), job['nudge'], job['token']))
            if status == '410':
                db.execute('DELETE FROM devices WHERE token=?', (job['token'],))
            remaining = db.execute("SELECT count(*) FROM push_jobs WHERE nudge=? AND state='pending'", (job['nudge'],)).fetchone()[0]
            if remaining == 0:
                sent = db.execute("SELECT count(*) FROM push_jobs WHERE nudge=? AND state='sent'", (job['nudge'],)).fetchone()[0]
                db.execute('UPDATE nudges SET delivery=? WHERE id=?', ('sent' if sent else 'in_app', job['nudge']))


def delivery_loop(store):
    while True:
        try:
            deliver_pending(store)
        except Exception as error:
            print(f'Push worker will retry: {type(error).__name__}', flush=True)
        time.sleep(5)
