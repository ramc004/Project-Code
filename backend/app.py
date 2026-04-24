from flask import Flask, request, jsonify
from email.message import EmailMessage
import smtplib
import sqlite3
import hashlib
import os
import json
from datetime import datetime, timedelta
from collections import defaultdict

app = Flask(__name__)

# Database Initiation

def init_db():
    conn = sqlite3.connect('users.db')
    c = conn.cursor()

    c.execute('''
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    c.execute('''
        CREATE TABLE IF NOT EXISTS bulbs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_email TEXT NOT NULL,
            bulb_id TEXT NOT NULL,
            bulb_name TEXT NOT NULL,
            room_name TEXT,
            is_simulated INTEGER DEFAULT 0,
            added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_email) REFERENCES users(email),
            UNIQUE(user_email, bulb_id)
        )
    ''')

    # Alter table is used instead of the CREATE statement above because the
    # is_simulated column was added after the initial schema
    # Wrapping it in a try/except means this won't crash if the column already exists 
    # SQLite raises OperationalError for duplicate column additions
    try:
        c.execute('ALTER TABLE bulbs ADD COLUMN is_simulated INTEGER DEFAULT 0')
    except sqlite3.OperationalError:
        pass

    c.execute('''
        CREATE TABLE IF NOT EXISTS bulb_usage_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_email TEXT NOT NULL,
            bulb_id TEXT NOT NULL,
            event_type TEXT NOT NULL,
            power INTEGER,
            brightness INTEGER,
            colour_temp INTEGER,
            hour_of_day INTEGER,
            minute_of_day INTEGER,
            day_of_week INTEGER,
            recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    c.execute('''
        CREATE TABLE IF NOT EXISTS schedules (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_email TEXT NOT NULL,
            bulb_id TEXT NOT NULL,
            schedule_name TEXT NOT NULL,
            schedule_type TEXT NOT NULL DEFAULT 'manual',
            trigger_hour INTEGER NOT NULL,
            trigger_minute INTEGER NOT NULL DEFAULT 0,
            end_hour INTEGER,
            end_minute INTEGER DEFAULT 0,
            action TEXT NOT NULL,
            brightness INTEGER,
            colour_temp INTEGER,
            is_enabled INTEGER DEFAULT 1,
            confidence REAL DEFAULT 1.0,
            source TEXT DEFAULT 'manual',
            days_of_week TEXT DEFAULT '1,2,3,4,5,6,7',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    c.execute('''
        CREATE TABLE IF NOT EXISTS health_sleep_data (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_email TEXT NOT NULL,
            sleep_start TEXT,
            sleep_end TEXT,
            wake_time TEXT,
            bedtime TEXT,
            source TEXT DEFAULT 'healthkit',
            recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    c.execute('''
        CREATE TABLE IF NOT EXISTS schedule_suggestions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_email TEXT NOT NULL,
            bulb_id TEXT NOT NULL,
            suggestion_type TEXT NOT NULL,
            trigger_hour INTEGER NOT NULL,
            trigger_minute INTEGER NOT NULL DEFAULT 0,
            window_start_hour INTEGER,
            window_start_minute INTEGER DEFAULT 0,
            window_end_hour INTEGER,
            window_end_minute INTEGER DEFAULT 0,
            action TEXT NOT NULL,
            brightness INTEGER,
            colour_temp INTEGER,
            confidence REAL NOT NULL,
            observation_count INTEGER DEFAULT 0,
            status TEXT DEFAULT 'pending',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    conn.commit()
    conn.close()

    _seed_test_data()
    print("Database initialised")

def _seed_test_data():
    conn = sqlite3.connect('users.db')
    c = conn.cursor()

    # Guard clause, if any usage events already exist the DB has already been
    # seeded, so return immediately to avoid duplicating test data on restart
    c.execute("SELECT COUNT(*) FROM bulb_usage_events")
    if c.fetchone()[0] > 0:
        conn.close()
        return

    print("Seeding test usage data…")
    now = datetime.now()

    events = []
    for day_offset in range(14):
        base = now - timedelta(days=day_offset)
        # weekday() returns 0–6 (Mon–Sun); +1 shifts it to the 1–7 convention
        # used throughout the app so Monday = 1 and Sunday = 7
        dow = base.weekday() + 1

        m_min = 25 + (day_offset % 3) * 3
        events.append(('test@example.com', 'demo-bulb-1', 'power_on',
                        1, 255, 200, 7, m_min, dow))

        e_min = 40 + (day_offset % 4) * 2
        events.append(('test@example.com', 'demo-bulb-1', 'brightness_change',
                        1, 60, 255, 21, e_min, dow))

        # When jitter pushes the minute value past 59 it wraps into the next
        # hour, so the hour is incremented to 22 and the minute is adjusted
        # accordingly to keep the timestamp accurate
        b_min = 55 + (day_offset % 3)
        if b_min >= 60:
            events.append(('test@example.com', 'demo-bulb-1', 'power_off',
                            0, 0, 255, 22, b_min - 60, dow))
        else:
            events.append(('test@example.com', 'demo-bulb-1', 'power_off',
                            0, 0, 255, 21, b_min, dow))

    # The list comprehension pairs each event tuple with its day_offset so the
    # recorded_at timestamp can be backdated using SQLite's datetime modifier,
    # simulating 14 days of real historical data in a single bulk insert
    c.executemany('''
        INSERT INTO bulb_usage_events
        (user_email, bulb_id, event_type, power, brightness, colour_temp,
         hour_of_day, minute_of_day, day_of_week, recorded_at)
        VALUES (?,?,?,?,?,?,?,?,?, datetime('now','-'||?||' days'))
    ''', [(e[0], e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8],
           str(day_offset)) for day_offset, e in
          [(i // 3, events[i]) for i in range(len(events))]])

    c.execute('''
        INSERT OR IGNORE INTO schedule_suggestions
        (user_email, bulb_id, suggestion_type,
         trigger_hour, trigger_minute,
         window_start_hour, window_start_minute,
         window_end_hour, window_end_minute,
         action, brightness, colour_temp,
         confidence, observation_count, status)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    ''', ('test@example.com', 'demo-bulb-1', 'auto_power_off',
          22, 0,
          21, 45, 22, 15,
          'power_off', 0, 255,
          0.87, 14, 'pending'))

    conn.commit()
    conn.close()
    print("Test data seeded.")

# Helpers
def hash_password(password):
    return hashlib.sha256(password.encode()).hexdigest()

def verify_password(stored_hash, provided_password):
    return stored_hash == hash_password(provided_password)

def get_db():
    return sqlite3.connect('users.db')

# Health Check
@app.route('/health', methods=['GET', 'POST'])
def health():
    return jsonify({'status': 'ok'}), 200

# Authentication Routes
@app.route('/send_code', methods=['POST'])
def send_code():
    data = request.get_json()
    email_recipient = data.get('email')
    code = data.get('code')

    # Basic format checks before touching the mail server, avoids using an
    # SMTP connection on a request that was always going to be invalid
    if not email_recipient or "@" not in email_recipient:
        return jsonify({'status': 'error', 'message': 'Invalid email'}), 400
    if not code or len(code) != 6:
        return jsonify({'status': 'error', 'message': 'Invalid code'}), 400

    email_recipient = email_recipient.strip()
    code = code.strip()

    try:
        with open("hello.txt", "r") as f:
            email_password = f.read().strip()

        email_sender = "ramcaleb50@gmail.com"
        sender_display_name = "Caleb's Home Automation System"

        msg = EmailMessage()
        msg["From"] = f"{sender_display_name} <{email_sender}>"
        msg["To"] = email_recipient
        msg["Subject"] = "Your Verification Code"

        email_body = f"""Hello,

Your 6-digit verification code is: {code}

This code will expire in 5 minutes. Please do not share this code with anyone.

If you did not request this code, please ignore this email.

Best regards,
Caleb's Home Automation System

---
This is an automated message. Please do not reply to this email."""

        msg.set_content(email_body)

        # SMTP_SSL opens a TLS-wrapped connection from the start on port 465,
        # unlike starttls() which upgrades a plain connection mid-session
        # The context manager guarantees the socket is closed even if sending fails
        with smtplib.SMTP_SSL("smtp.gmail.com", 465) as server:
            server.login(email_sender, email_password)
            server.send_message(msg)

        return jsonify({'status': 'success', 'code': code})
    except Exception as e:
        print(f"Failed to send email: {e}")
        return jsonify({'status': 'error', 'message': 'Failed to send email'}), 500

@app.route('/check_email', methods=['POST'])
def check_email():
    data = request.get_json()
    email = data.get('email', '').strip()
    if not email:
        return jsonify({'status': 'error', 'message': 'Email is required'}), 400
    try:
        conn = get_db(); c = conn.cursor()
        c.execute('SELECT id FROM users WHERE email = ?', (email,))
        user = c.fetchone(); conn.close()
        # Returns available: true when no row is found, so the client knows
        # whether it can proceed with registration without a separate error path
        return jsonify({'status': 'success', 'available': user is None})
    except Exception as e:
        return jsonify({'status': 'error', 'message': 'Database error'}), 500

@app.route('/register', methods=['POST'])
def register():
    data = request.get_json()
    email = data.get('email', '').strip()
    password = data.get('password', '')

    if not email or not password:
        return jsonify({'status': 'error', 'message': 'Email and password are required'}), 400

    # Split on '@' and inspect the domain segment to catch formats like
    # "user@nodot" that pass a simple '@' check but aren't valid addresses
    if '@' not in email or '.' not in email.split('@')[1]:
        return jsonify({'status': 'error', 'message': 'Invalid email format'}), 400

    if len(password) < 8:
        return jsonify({'status': 'error', 'message': 'Password must be at least 8 characters'}), 400

    try:
        conn = get_db(); c = conn.cursor()
        c.execute('SELECT id FROM users WHERE email = ?', (email,))
        if c.fetchone():
            conn.close()
            return jsonify({'status': 'error', 'message': 'Email already registered'}), 409
        c.execute('INSERT INTO users (email, password_hash) VALUES (?, ?)',
                  (email, hash_password(password)))
        conn.commit(); conn.close()
        return jsonify({'status': 'success', 'message': 'User registered successfully'})
    # IntegrityError is caught separately from the generic Exception because it
    # represents a race condition where two requests register the same email at
    # the same instant, the DB constraint fires even if the SELECT above missed it
    except sqlite3.IntegrityError:
        return jsonify({'status': 'error', 'message': 'Email already registered'}), 409
    except Exception as e:
        return jsonify({'status': 'error', 'message': 'Registration failed'}), 500

@app.route('/login', methods=['POST'])
def login():
    data = request.get_json()
    email = data.get('email', '').strip()
    password = data.get('password', '')
    if not email or not password:
        return jsonify({'status': 'error', 'message': 'Email and password are required'}), 400
    try:
        conn = get_db(); c = conn.cursor()
        c.execute('SELECT password_hash FROM users WHERE email = ?', (email,))
        user = c.fetchone(); conn.close()
        if not user:
            return jsonify({'status': 'error', 'message': 'Email not registered'}), 404
        if verify_password(user[0], password):
            return jsonify({'status': 'success', 'message': 'Login successful'})
        return jsonify({'status': 'error', 'message': 'Incorrect password'}), 401
    except Exception as e:
        return jsonify({'status': 'error', 'message': 'Login failed'}), 500

@app.route('/reset_password', methods=['POST'])
def reset_password():
    data = request.get_json()
    email = data.get('email', '').strip()
    new_password = data.get('password', '')
    if not email or not new_password:
        return jsonify({'status': 'error', 'message': 'Email and password are required'}), 400
    try:
        conn = get_db(); c = conn.cursor()
        # Confirm the account exists before hashing and writing, so the
        # caller receives a clear 404 rather than a silent update
        c.execute('SELECT id FROM users WHERE email = ?', (email,))
        if not c.fetchone():
            conn.close()
            return jsonify({'status': 'error', 'message': 'Email not registered'}), 404
        c.execute('UPDATE users SET password_hash = ? WHERE email = ?',
                  (hash_password(new_password), email))
        conn.commit(); conn.close()
        return jsonify({'status': 'success', 'message': 'Password reset successful'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': 'Password reset failed'}), 500

# Bulb Routes
@app.route('/add_bulb', methods=['POST'])
def add_bulb():
    data = request.get_json()
    user_email = data.get('email', '').strip()
    bulb_id = data.get('bulb_id', '').strip()
    bulb_name = data.get('bulb_name', '').strip()
    room_name = data.get('room_name', '').strip()
    is_simulated = data.get('is_simulated', False)
    if not user_email or not bulb_id or not bulb_name:
        return jsonify({'status': 'error', 'message': 'Email, bulb_id, and bulb_name are required'}), 400
    try:
        conn = get_db(); c = conn.cursor()
        c.execute('SELECT id FROM users WHERE email = ?', (user_email,))
        if not c.fetchone():
            conn.close()
            return jsonify({'status': 'error', 'message': 'User not found'}), 404
        c.execute('SELECT id FROM bulbs WHERE user_email = ? AND bulb_id = ?', (user_email, bulb_id))
        if c.fetchone():
            conn.close()
            return jsonify({'status': 'error', 'message': 'Bulb already added'}), 409
        # SQLite stores booleans as integers; the ternary converts the incoming
        # Python/JSON bool to 1/0 explicitly so queries on is_simulated are consistent
        c.execute('INSERT INTO bulbs (user_email, bulb_id, bulb_name, room_name, is_simulated) VALUES (?,?,?,?,?)',
                  (user_email, bulb_id, bulb_name, room_name, 1 if is_simulated else 0))
        conn.commit(); conn.close()
        return jsonify({'status': 'success', 'message': 'Bulb added successfully'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': 'Failed to add bulb'}), 500

@app.route('/get_bulbs', methods=['POST'])
def get_bulbs():
    data = request.get_json()
    user_email = data.get('email', '').strip()
    simulator_mode = data.get('simulator_mode', True)
    if not user_email:
        return jsonify({'status': 'error', 'message': 'Email is required'}), 400
    try:
        conn = get_db(); c = conn.cursor()
        # The query is chosen at runtime based on simulator_mode so the app can
        # show either virtual demo bulbs or real paired hardware without
        # returning both mixed together in the same list
        if simulator_mode:
            q = 'SELECT bulb_id, bulb_name, room_name, added_at, last_seen, is_simulated FROM bulbs WHERE user_email = ? AND is_simulated = 1 ORDER BY added_at DESC'
        else:
            q = 'SELECT bulb_id, bulb_name, room_name, added_at, last_seen, is_simulated FROM bulbs WHERE user_email = ? AND (is_simulated = 0 OR is_simulated IS NULL) ORDER BY added_at DESC'
        c.execute(q, (user_email,))
        bulbs = []
        for row in c.fetchall():
            # is_simulated may be NULL for older rows inserted before the column
            # existed, so the conditional None check prevents bool(None) = False
            # from silently misclassifying legacy bulbs
            bulbs.append({'bulb_id': row[0], 'bulb_name': row[1], 'room_name': row[2],
                          'added_at': row[3], 'last_seen': row[4],
                          'is_simulated': bool(row[5]) if row[5] is not None else False})
        conn.close()
        return jsonify({'status': 'success', 'bulbs': bulbs})
    except Exception as e:
        return jsonify({'status': 'error', 'message': 'Failed to retrieve bulbs'}), 500

@app.route('/update_bulb', methods=['POST'])
def update_bulb():
    data = request.get_json()
    user_email = data.get('email', '').strip()
    bulb_id = data.get('bulb_id', '').strip()
    bulb_name = data.get('bulb_name')
    room_name = data.get('room_name')
    if not user_email or not bulb_id:
        return jsonify({'status': 'error', 'message': 'Email and bulb_id are required'}), 400
    try:
        conn = get_db(); c = conn.cursor()
        # Only fields actually present in the request are added to the UPDATE
        # statement, preventing accidental overwrites of fields the caller
        # didn't intend to change and keeping the query minimal.
        updates, params = [], []
        if bulb_name: updates.append('bulb_name = ?'); params.append(bulb_name.strip())
        if room_name: updates.append('room_name = ?'); params.append(room_name.strip())
        if not updates:
            conn.close()
            return jsonify({'status': 'error', 'message': 'Nothing to update'}), 400
        params.extend([user_email, bulb_id])
        c.execute(f"UPDATE bulbs SET {', '.join(updates)} WHERE user_email = ? AND bulb_id = ?", params)
        conn.commit(); conn.close()
        return jsonify({'status': 'success', 'message': 'Bulb updated successfully'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': 'Failed to update bulb'}), 500

@app.route('/delete_bulb', methods=['POST'])
def delete_bulb():
    data = request.get_json()
    user_email = data.get('email', '').strip()
    bulb_id = data.get('bulb_id', '').strip()
    if not user_email or not bulb_id:
        return jsonify({'status': 'error', 'message': 'Email and bulb_id are required'}), 400
    try:
        conn = get_db(); c = conn.cursor()
        c.execute('DELETE FROM bulbs WHERE user_email = ? AND bulb_id = ?', (user_email, bulb_id))
        # rowcount is 0 when the where clause matched nothing, meaning the bulb
        # either never existed or belongs to a different user, return 404 rather
        # than silently claiming success
        if c.rowcount == 0:
            conn.close()
            return jsonify({'status': 'error', 'message': 'Bulb not found'}), 404
        conn.commit(); conn.close()
        return jsonify({'status': 'success', 'message': 'Bulb deleted successfully'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': 'Failed to delete bulb'}), 500

# Usage logging
@app.route('/log_usage', methods=['POST'])
def log_usage():
    data = request.get_json()
    user_email = data.get('email', '').strip()
    bulb_id = data.get('bulb_id', '').strip()
    event_type = data.get('event_type', '')
    power = data.get('power')
    brightness = data.get('brightness')
    colour_temp = data.get('colour_temp')
    if not user_email or not bulb_id or not event_type:
        return jsonify({'status': 'error', 'message': 'Missing fields'}), 400
    now = datetime.now()
    try:
        conn = get_db(); c = conn.cursor()
        # hour_of_day, minute_of_day, and day_of_week are stored as separate
        # integer columns rather than just recorded_at so the ML analysis can
        # group and aggregate by time-of-day directly in SQL without string parsing
        c.execute('''
            INSERT INTO bulb_usage_events
            (user_email, bulb_id, event_type, power, brightness, colour_temp,
             hour_of_day, minute_of_day, day_of_week)
            VALUES (?,?,?,?,?,?,?,?,?)
        ''', (user_email, bulb_id, event_type, power, brightness, colour_temp,
              now.hour, now.minute, now.weekday() + 1))
        conn.commit(); conn.close()
        return jsonify({'status': 'success'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500


# Sleep and health data
@app.route('/sync_sleep', methods=['POST'])
def sync_sleep():
    data = request.get_json()
    user_email = data.get('email', '').strip()
    sleep_start = data.get('sleep_start')
    sleep_end = data.get('sleep_end')
    if not user_email:
        return jsonify({'status': 'error', 'message': 'Email required'}), 400
    try:
        conn = get_db(); c = conn.cursor()
        # wake_time and bedtime mirror sleep_end/sleep_start respectively so
        # queries can use semantic column names rather than remembering which
        # direction sleep_start and sleep_end refer to
        c.execute('''
            INSERT INTO health_sleep_data (user_email, sleep_start, sleep_end, wake_time, bedtime, source)
            VALUES (?,?,?,?,?,?)
        ''', (user_email, sleep_start, sleep_end, sleep_end, sleep_start, 'healthkit'))
        conn.commit(); conn.close()
        _generate_sleep_suggestions(user_email, sleep_start, sleep_end)
        return jsonify({'status': 'success'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500

def _generate_sleep_suggestions(user_email, sleep_start_iso, wake_time_iso):
    import math
    try:
        # ISO strings from HealthKit may include timezone offsets or milliseconds;
        # slicing to [:19] strips everything past the seconds component so
        # fromisoformat() doesn't raise on extended formats
        sleep_dt = datetime.fromisoformat(sleep_start_iso[:19])
        wake_dt  = datetime.fromisoformat(wake_time_iso[:19])

        wd = sleep_dt - timedelta(minutes=15)
        wu = wake_dt  - timedelta(minutes=15)

        conn = get_db(); c = conn.cursor()

        c.execute('SELECT bulb_id FROM bulbs WHERE user_email = ? LIMIT 1', (user_email,))
        row = c.fetchone()
        bulb_id = row[0] if row else 'demo-bulb-1'

        c.execute('''
            SELECT COUNT(*) FROM health_sleep_data
            WHERE user_email = ?
              AND recorded_at >= datetime('now', '-30 days')
        ''', (user_email,))
        nights = max(c.fetchone()[0] or 1, 1)

        # Sigmoid curve scales confidence from ~0.42 at 1 night up to a hard
        # ceiling of 0.75 — the inflection point is at 7 nights (one week)
        # where confidence reaches roughly 0.62. This prevents a single night
        # of data from generating an overconfident suggestion
        sleep_confidence = min(round(0.75 / (1.0 + math.exp(-0.25 * (nights - 7))), 2), 0.75)

        for stype, dt, action, brightness, colour_temp in [
            ('sleep_wind_down', wd, 'dim_warm',       40,  255),
            ('sleep_wake_up',   wu, 'brighten_cool', 200,   80),
        ]:
            # Before inserting, check whether a pending suggestion for this
            # exact type and time already exists, HealthKit can sync the same
            # night multiple times, and this prevents duplicate cards appearing
            # in the user's suggestion list
            c.execute('''
                SELECT id FROM schedule_suggestions
                WHERE user_email=? AND bulb_id=? AND suggestion_type=?
                  AND trigger_hour=? AND trigger_minute=? AND status='pending'
            ''', (user_email, bulb_id, stype, dt.hour, dt.minute))
            if c.fetchone():
                continue

            c.execute('''
                INSERT INTO schedule_suggestions
                (user_email, bulb_id, suggestion_type, trigger_hour, trigger_minute,
                 action, brightness, colour_temp, confidence, observation_count, status)
                VALUES (?,?,?,?,?,?,?,?,?,?,?)
            ''', (user_email, bulb_id, stype, dt.hour, dt.minute,
                  action, brightness, colour_temp, sleep_confidence, nights, 'pending'))

        conn.commit(); conn.close()
    except Exception as e:
        print(f"Sleep suggestion error: {e}")

# Machine Learning: Analyse Usage & Generate Suggestions
@app.route('/analyse_usage', methods=['POST'])
def analyse_usage():
    """
    Multi-factor confidence model:

      confidence = consistency × sample_weight × recency_weight

      consistency   = distinct days this pattern fired / days the app was used
      sample_weight = sigmoid ramp over distinct days of evidence
      recency_weight= fraction of occurrences in the last 7 days, scaled 0.70–1.00

    Hard ceiling: 0.82
    Minimum to surface: 0.40
    """
    import math

    data = request.get_json()
    user_email = data.get('email', '').strip()
    bulb_id    = data.get('bulb_id', '').strip()
    if not user_email or not bulb_id:
        return jsonify({'status': 'error', 'message': 'Missing fields'}), 400

    conn = get_db(); c = conn.cursor()

    c.execute('''
        SELECT event_type, hour_of_day, minute_of_day, brightness, colour_temp,
               date(recorded_at), recorded_at
        FROM bulb_usage_events
        WHERE user_email = ? AND bulb_id = ?
          AND recorded_at >= datetime('now', '-28 days')
        ORDER BY recorded_at ASC
    ''', (user_email, bulb_id))
    events = c.fetchall()

    # Using a set of date strings as the denominator means consistency is
    # relative to days the user actually opened the app, not calendar days 
    # this avoids penalising patterns on days the app was never used
    active_days       = set(row[5] for row in events)
    total_active_days = max(len(active_days), 1)

    # Events are collapsed into 30-minute slots before bucketing. The seen_day_buckets
    # set ensures that if a user taps the bulb five times within the same half-hour
    # on the same day, it only counts as one occurrence, preventing repeat
    # interactions from artificially inflating a pattern's frequency score
    seen_day_buckets = set()
    buckets          = defaultdict(list)

    for ev_type, h, m, brightness, col, date_str, recorded_at in events:
        slot    = 0 if m < 30 else 30
        key     = (ev_type, h, slot)
        day_key = (ev_type, h, slot, date_str)
        if day_key in seen_day_buckets:
            continue
        seen_day_buckets.add(day_key)
        buckets[key].append({
            'brightness':  brightness,
            'colour_temp': col,
            'date':        date_str,
            'recorded_at': recorded_at,
        })

    now_str           = datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')
    week_ago_str      = (datetime.utcnow() - timedelta(days=7)).strftime('%Y-%m-%d %H:%M:%S')
    suggestions_created = 0

    for (ev_type, h, bm), entries in buckets.items():
        n = len(entries)

        consistency = n / total_active_days

        # Sigmoid sample weight: at n=2 days the weight is ~0.50 (low confidence),
        # rising to ~0.72 at 7 days and ~0.90 at 14
        # The -7 shift centres the inflection point at one week of evidence
        sample_weight = 1.0 / (1.0 + math.exp(-0.35 * (n - 7)))

        # Recency weight floors at 0.70 so old patterns aren't zeroed out entirely
        # they're penalised but still eligible if their consistency is strong enough
        recent        = sum(1 for e in entries if e['recorded_at'] >= week_ago_str)
        recency_ratio  = recent / n
        recency_weight = 0.70 + 0.30 * recency_ratio

        confidence = min(round(consistency * sample_weight * recency_weight, 2), 0.82)

        if confidence < 0.40:
            continue

        # Median is used instead of mean for brightness and colour_temp because
        # it's resistant to outliers, a single accidental maximum-brightness
        # event won't skew the suggested setting away from the user's typical choice
        brights = [e['brightness']  for e in entries if e['brightness']  is not None]
        cols    = [e['colour_temp'] for e in entries if e['colour_temp'] is not None]
        med_b   = int(sorted(brights)[len(brights) // 2]) if brights else 255
        med_c   = int(sorted(cols)[len(cols) // 2])       if cols    else 128

        # Action is inferred from event type first; for brightness_change events
        # the median brightness determines whether this looks like a wind-down
        # dim (≤80) or a general adjustment, giving the suggestion a meaningful label
        if ev_type == 'power_off':
            action = 'power_off'
        elif ev_type == 'power_on':
            action = 'power_on'
        elif med_b <= 80:
            action = 'dim_warm'
        else:
            action = 'brightness_change'

        # The trigger is placed at the midpoint of the 30-minute slot window
        # (bm + 15 min) rather than at its start, giving the app a reasonable
        # target time while the window bounds are stored for display purposes
        w_start_h, w_start_m = h, bm
        w_end_m = bm + 30;   w_end_h = h
        if w_end_m >= 60:    w_end_m -= 60; w_end_h += 1
        trigger_m = bm + 15; trigger_h = h
        if trigger_m >= 60:  trigger_m -= 60; trigger_h += 1

        # Deduplication check prevents re-inserting a suggestion that's already pending
        # analyse_usage can be called repeatedly and should be idempotent
        c.execute('''
            SELECT id FROM schedule_suggestions
            WHERE user_email=? AND bulb_id=? AND suggestion_type=?
              AND trigger_hour=? AND trigger_minute=? AND status='pending'
        ''', (user_email, bulb_id, 'auto_' + ev_type, trigger_h, trigger_m))
        if c.fetchone():
            continue

        c.execute('''
            INSERT INTO schedule_suggestions
            (user_email, bulb_id, suggestion_type, trigger_hour, trigger_minute,
             window_start_hour, window_start_minute, window_end_hour, window_end_minute,
             action, brightness, colour_temp, confidence, observation_count, status)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ''', (user_email, bulb_id, 'auto_' + ev_type,
              trigger_h, trigger_m,
              w_start_h, w_start_m, w_end_h, w_end_m,
              action, med_b, med_c,
              confidence, n, 'pending'))
        suggestions_created += 1

    conn.commit(); conn.close()
    return jsonify({'status': 'success', 'suggestions_created': suggestions_created,
                    'days_analysed': total_active_days, 'events_processed': len(events)})

# Suggestions
@app.route('/get_suggestions', methods=['POST'])
def get_suggestions():
    data = request.get_json()
    user_email = data.get('email', '').strip()
    bulb_id = data.get('bulb_id', '').strip()
    try:
        conn = get_db(); c = conn.cursor()
        q = '''SELECT id, suggestion_type, trigger_hour, trigger_minute,
                      window_start_hour, window_start_minute,
                      window_end_hour, window_end_minute,
                      action, brightness, colour_temp,
                      confidence, observation_count, status, created_at
               FROM schedule_suggestions
               WHERE user_email = ? AND status = 'pending'
            '''
        params = [user_email]
        # bulb_id filter is optional, if omitted, all pending suggestions for
        # the user are returned regardless of which bulb they target
        if bulb_id:
            q += ' AND bulb_id = ?'; params.append(bulb_id)
        q += ' ORDER BY confidence DESC'
        c.execute(q, params)
        rows = c.fetchall()
        conn.close()
        result = []
        for r in rows:
            result.append({
                'id': r[0], 'suggestion_type': r[1],
                'trigger_hour': r[2], 'trigger_minute': r[3],
                'window_start_hour': r[4], 'window_start_minute': r[5],
                'window_end_hour': r[6], 'window_end_minute': r[7],
                'action': r[8], 'brightness': r[9], 'colour_temp': r[10],
                'confidence': r[11], 'observation_count': r[12],
                'status': r[13], 'created_at': r[14]
            })
        return jsonify({'status': 'success', 'suggestions': result})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500


@app.route('/respond_suggestion', methods=['POST'])
def respond_suggestion():
    data = request.get_json()
    suggestion_id = data.get('suggestion_id')
    response = data.get('response')
    user_email = data.get('email', '').strip()
    if not suggestion_id or not response:
        return jsonify({'status': 'error', 'message': 'Missing fields'}), 400
    try:
        conn = get_db(); c = conn.cursor()
        c.execute('''
            SELECT id, bulb_id, suggestion_type, trigger_hour, trigger_minute,
                   action, brightness, colour_temp, confidence
            FROM schedule_suggestions WHERE id = ?
        ''', (suggestion_id,))
        s = c.fetchone()
        if not s:
            conn.close()
            return jsonify({'status': 'error', 'message': 'Suggestion not found'}), 404

        if response == 'dismiss':
            c.execute("UPDATE schedule_suggestions SET status='dismissed' WHERE id=?", (suggestion_id,))
        else:
            # Accepting or auto-approving a suggestion promotes it directly into
            # the schedules table with source='auto', so it runs like any other
            # schedule, the name is derived from the suggestion_type to give the
            # user a readable label without requiring them to name it manually
            c.execute('''
                INSERT INTO schedules
                (user_email, bulb_id, schedule_name, schedule_type,
                 trigger_hour, trigger_minute, action,
                 brightness, colour_temp, confidence, source, is_enabled)
                VALUES (?,?,?,?,?,?,?,?,?,?,'auto',1)
            ''', (user_email, s[1],
                  f"Auto: {s[2].replace('_', ' ').title()}",
                  'auto', s[3], s[4], s[5], s[6], s[7], s[8]))
            c.execute("UPDATE schedule_suggestions SET status='accepted' WHERE id=?", (suggestion_id,))
        conn.commit(); conn.close()
        return jsonify({'status': 'success'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500

# Schedules
@app.route('/get_schedules', methods=['POST'])
def get_schedules():
    data = request.get_json()
    user_email = data.get('email', '').strip()
    bulb_id = data.get('bulb_id', '').strip()
    try:
        conn = get_db(); c = conn.cursor()
        q = '''SELECT id, bulb_id, schedule_name, schedule_type,
                      trigger_hour, trigger_minute, end_hour, end_minute,
                      action, brightness, colour_temp, is_enabled,
                      confidence, source, days_of_week
               FROM schedules WHERE user_email = ?'''
        params = [user_email]
        if bulb_id:
            q += ' AND bulb_id = ?'; params.append(bulb_id)
        q += ' ORDER BY trigger_hour, trigger_minute'
        c.execute(q, params)
        rows = c.fetchall()
        conn.close()
        result = []
        for r in rows:
            result.append({
                'id': r[0], 'bulb_id': r[1], 'schedule_name': r[2],
                'schedule_type': r[3],
                'trigger_hour': r[4], 'trigger_minute': r[5],
                'end_hour': r[6], 'end_minute': r[7],
                'action': r[8], 'brightness': r[9], 'colour_temp': r[10],
                'is_enabled': bool(r[11]), 'confidence': r[12],
                'source': r[13], 'days_of_week': r[14]
            })
        return jsonify({'status': 'success', 'schedules': result})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500


@app.route('/add_schedule', methods=['POST'])
def add_schedule():
    data = request.get_json()
    user_email = data.get('email', '').strip()
    bulb_id = data.get('bulb_id', '').strip()
    schedule_name = data.get('schedule_name', '').strip()
    trigger_hour = data.get('trigger_hour')
    trigger_minute = data.get('trigger_minute', 0)
    action = data.get('action', 'power_on')
    brightness = data.get('brightness', 255)
    colour_temp = data.get('colour_temp', 128)
    days = data.get('days_of_week', '1,2,3,4,5,6,7')
    end_hour = data.get('end_hour')
    end_minute = data.get('end_minute', 0)
    if not user_email or not bulb_id or not schedule_name or trigger_hour is None:
        return jsonify({'status': 'error', 'message': 'Missing required fields'}), 400
    try:
        conn = get_db(); c = conn.cursor()
        c.execute('''
            INSERT INTO schedules
            (user_email, bulb_id, schedule_name, schedule_type,
             trigger_hour, trigger_minute, end_hour, end_minute,
             action, brightness, colour_temp, source, days_of_week, confidence)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,'manual',?,1.0)
        ''', (user_email, bulb_id, schedule_name, 'manual',
              trigger_hour, trigger_minute, end_hour, end_minute,
              action, brightness, colour_temp, days))
        # lastrowid returns the primary key of the row just inserted, sent back
        # to the client so it can reference this schedule immediately without
        # a follow-up fetch
        schedule_id = c.lastrowid
        conn.commit(); conn.close()
        return jsonify({'status': 'success', 'schedule_id': schedule_id})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500


@app.route('/update_schedule', methods=['POST'])
def update_schedule():
    data = request.get_json()
    schedule_id = data.get('schedule_id')
    user_email = data.get('email', '').strip()
    if not schedule_id or not user_email:
        return jsonify({'status': 'error', 'message': 'Missing fields'}), 400
    try:
        conn = get_db(); c = conn.cursor()
        # The whitelist of updatable fields prevents arbitrary column injection
        # through the request body — only fields in this list can be modified
        # regardless of what the caller sends
        updatable = ['schedule_name', 'trigger_hour', 'trigger_minute', 'end_hour', 'end_minute',
                     'action', 'brightness', 'colour_temp', 'is_enabled', 'days_of_week']
        updates, params = [], []
        for field in updatable:
            if field in data:
                updates.append(f'{field} = ?')
                params.append(data[field])
        if not updates:
            conn.close()
            return jsonify({'status': 'error', 'message': 'Nothing to update'}), 400
        params.extend([schedule_id, user_email])
        c.execute(f"UPDATE schedules SET {', '.join(updates)} WHERE id=? AND user_email=?", params)
        conn.commit(); conn.close()
        return jsonify({'status': 'success'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500


@app.route('/delete_schedule', methods=['POST'])
def delete_schedule():
    data = request.get_json()
    schedule_id = data.get('schedule_id')
    user_email = data.get('email', '').strip()
    if not schedule_id or not user_email:
        return jsonify({'status': 'error', 'message': 'Missing fields'}), 400
    try:
        conn = get_db(); c = conn.cursor()
        # user_email is included in the WHERE clause so one user cannot delete
        # another user's schedules by guessing a schedule_id
        c.execute('DELETE FROM schedules WHERE id=? AND user_email=?', (schedule_id, user_email))
        conn.commit(); conn.close()
        return jsonify({'status': 'success'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500


# Entry point
if __name__ == "__main__":
    init_db()
    print("Flask Server Starting…")
    app.run(debug=True, host='0.0.0.0', port=5000)
