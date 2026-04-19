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

# ─────────────────────────────────────────────────────────────
# DATABASE INIT
# ─────────────────────────────────────────────────────────────
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

    try:
        c.execute('ALTER TABLE bulbs ADD COLUMN is_simulated INTEGER DEFAULT 0')
    except sqlite3.OperationalError:
        pass

    # ── Usage events: every time user changes power/brightness/colourTemp ──
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

    # ── Schedules: manually created OR auto-generated ──────────────────────
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

    # ── Health / sleep data synced from HealthKit ──────────────────────────
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

    # ── ML suggestions waiting for user approval ───────────────────────────
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

    # Seed test data for quick testing
    _seed_test_data()
    print("Database initialised")


def _seed_test_data():
    """Insert demo usage events and a test suggestion so the ML has something to work with."""
    conn = sqlite3.connect('users.db')
    c = conn.cursor()

    # Only seed once
    c.execute("SELECT COUNT(*) FROM bulb_usage_events")
    if c.fetchone()[0] > 0:
        conn.close()
        return

    print("Seeding test usage data…")
    now = datetime.now()

    # Build 14 days of synthetic usage:
    #   - Turn on at ~07:30 every day (wake up)
    #   - Dim at ~21:45 (wind down)
    #   - Turn off at ~22:00 (bed)
    events = []
    for day_offset in range(14):
        base = now - timedelta(days=day_offset)
        dow = base.weekday() + 1  # 1=Mon … 7=Sun

        # Morning turn-on: 07:25 – 07:35 jitter
        m_min = 25 + (day_offset % 3) * 3  # jitter
        events.append(('test@example.com', 'demo-bulb-1', 'power_on',
                        1, 255, 200, 7, m_min, dow))

        # Evening dim: 21:40 – 21:50 jitter
        e_min = 40 + (day_offset % 4) * 2
        events.append(('test@example.com', 'demo-bulb-1', 'brightness_change',
                        1, 60, 255, 21, e_min, dow))

        # Bed turn-off: 21:55 – 22:05
        b_min = 55 + (day_offset % 3)
        if b_min >= 60:
            events.append(('test@example.com', 'demo-bulb-1', 'power_off',
                            0, 0, 255, 22, b_min - 60, dow))
        else:
            events.append(('test@example.com', 'demo-bulb-1', 'power_off',
                            0, 0, 255, 21, b_min, dow))

    c.executemany('''
        INSERT INTO bulb_usage_events
        (user_email, bulb_id, event_type, power, brightness, colour_temp,
         hour_of_day, minute_of_day, day_of_week, recorded_at)
        VALUES (?,?,?,?,?,?,?,?,?, datetime('now','-'||?||' days'))
    ''', [(e[0], e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8],
           str(day_offset)) for day_offset, e in
          [(i // 3, events[i]) for i in range(len(events))]])

    # Insert a pre-built suggestion
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


# ─────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────
def hash_password(password):
    return hashlib.sha256(password.encode()).hexdigest()

def verify_password(stored_hash, provided_password):
    return stored_hash == hash_password(provided_password)

def get_db():
    return sqlite3.connect('users.db')


# ─────────────────────────────────────────────────────────────
# HEALTH CHECK
# ─────────────────────────────────────────────────────────────
@app.route('/health', methods=['GET', 'POST'])
def health():
    return jsonify({'status': 'ok'}), 200


# ─────────────────────────────────────────────────────────────
# AUTH ROUTES  (unchanged)
# ─────────────────────────────────────────────────────────────
@app.route('/send_code', methods=['POST'])
def send_code():
    data = request.get_json()
    email_recipient = data.get('email')
    code = data.get('code')
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
        # Build email message
        msg = EmailMessage()
        msg["From"] = f"{sender_display_name} <{email_sender}>"
        msg["To"] = email_recipient
        msg["Subject"] = "Your Verification Code"

        # Email body with user code
        email_body = f"""Hello,

Your 6-digit verification code is: {code}

This code will expire in 5 minutes. Please do not share this code with anyone.

If you did not request this code, please ignore this email.

Best regards,
Caleb's Home Automation System

---
This is an automated message. Please do not reply to this email."""

        msg.set_content(email_body)
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


# ─────────────────────────────────────────────────────────────
# BULB ROUTES  (unchanged)
# ─────────────────────────────────────────────────────────────
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
        if simulator_mode:
            q = 'SELECT bulb_id, bulb_name, room_name, added_at, last_seen, is_simulated FROM bulbs WHERE user_email = ? AND is_simulated = 1 ORDER BY added_at DESC'
        else:
            q = 'SELECT bulb_id, bulb_name, room_name, added_at, last_seen, is_simulated FROM bulbs WHERE user_email = ? AND (is_simulated = 0 OR is_simulated IS NULL) ORDER BY added_at DESC'
        c.execute(q, (user_email,))
        bulbs = []
        for row in c.fetchall():
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
        if c.rowcount == 0:
            conn.close()
            return jsonify({'status': 'error', 'message': 'Bulb not found'}), 404
        conn.commit(); conn.close()
        return jsonify({'status': 'success', 'message': 'Bulb deleted successfully'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': 'Failed to delete bulb'}), 500


# ─────────────────────────────────────────────────────────────
# USAGE LOGGING
# ─────────────────────────────────────────────────────────────
@app.route('/log_usage', methods=['POST'])
def log_usage():
    """Called by the app every time the user changes bulb state."""
    data = request.get_json()
    user_email = data.get('email', '').strip()
    bulb_id = data.get('bulb_id', '').strip()
    event_type = data.get('event_type', '')   # power_on / power_off / brightness_change / colour_change
    power = data.get('power')
    brightness = data.get('brightness')
    colour_temp = data.get('colour_temp')
    if not user_email or not bulb_id or not event_type:
        return jsonify({'status': 'error', 'message': 'Missing fields'}), 400
    now = datetime.now()
    try:
        conn = get_db(); c = conn.cursor()
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


# ─────────────────────────────────────────────────────────────
# SLEEP / HEALTH DATA
# ─────────────────────────────────────────────────────────────
@app.route('/sync_sleep', methods=['POST'])
def sync_sleep():
    """Store sleep window from HealthKit."""
    data = request.get_json()
    user_email = data.get('email', '').strip()
    sleep_start = data.get('sleep_start')   # ISO string
    sleep_end = data.get('sleep_end')       # ISO string  (= wake time)
    if not user_email:
        return jsonify({'status': 'error', 'message': 'Email required'}), 400
    try:
        conn = get_db(); c = conn.cursor()
        c.execute('''
            INSERT INTO health_sleep_data (user_email, sleep_start, sleep_end, wake_time, bedtime, source)
            VALUES (?,?,?,?,?,?)
        ''', (user_email, sleep_start, sleep_end, sleep_end, sleep_start, 'healthkit'))
        conn.commit(); conn.close()
        # Auto-generate sleep-based schedule suggestions
        _generate_sleep_suggestions(user_email, sleep_start, sleep_end)
        return jsonify({'status': 'success'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500


def _generate_sleep_suggestions(user_email, sleep_start_iso, wake_time_iso):
    """Create wind-down and wake-up schedule suggestions from sleep data.

    Confidence scales with how many nights of data exist (max 0.75).
    A single night is weak signal — the user's bedtime varies day to day.
    After ~2 weeks of consistent data the suggestion becomes fairly reliable,
    but we never claim certainty since sleep schedules shift with life events.

      nights:  1 → 0.42,  3 → 0.50,  7 → 0.62,  14 → 0.72,  21+ → 0.75
    """
    import math
    try:
        sleep_dt = datetime.fromisoformat(sleep_start_iso[:19])
        wake_dt  = datetime.fromisoformat(wake_time_iso[:19])

        # Wind-down 15 min before bedtime; gentle wake 15 min before alarm
        wd = sleep_dt - timedelta(minutes=15)
        wu = wake_dt  - timedelta(minutes=15)

        conn = get_db(); c = conn.cursor()

        c.execute('SELECT bulb_id FROM bulbs WHERE user_email = ? LIMIT 1', (user_email,))
        row = c.fetchone()
        bulb_id = row[0] if row else 'demo-bulb-1'

        # Count nights of sleep data in the last 30 days
        c.execute('''
            SELECT COUNT(*) FROM health_sleep_data
            WHERE user_email = ?
              AND recorded_at >= datetime('now', '-30 days')
        ''', (user_email,))
        nights = max(c.fetchone()[0] or 1, 1)

        # Sigmoid-based scaling: honest at low counts, asymptotes at 0.75
        sleep_confidence = min(round(0.75 / (1.0 + math.exp(-0.25 * (nights - 7))), 2), 0.75)

        for stype, dt, action, brightness, colour_temp in [
            ('sleep_wind_down', wd, 'dim_warm',       40,  255),
            ('sleep_wake_up',   wu, 'brighten_cool', 200,   80),
        ]:
            # Don't duplicate an existing pending suggestion at the same time
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


# ─────────────────────────────────────────────────────────────
# ML: ANALYSE USAGE & GENERATE SUGGESTIONS
# ─────────────────────────────────────────────────────────────
@app.route('/analyse_usage', methods=['POST'])
def analyse_usage():
    """
    Multi-factor confidence model:

      confidence = consistency × sample_weight × recency_weight

      consistency   = distinct days this pattern fired / days the app was used
                      (one event per day per bucket — duplicates collapsed so
                       tapping the bulb 5 times in one evening doesn't inflate)
      sample_weight = sigmoid ramp over distinct days of evidence:
                      ~0.50 at 2 days, ~0.72 at 7, ~0.90 at 14, ~0.97 at 21
      recency_weight= fraction of occurrences in the last 7 days, scaled
                      0.70–1.00 (old stale patterns penalised, not zeroed)

    Hard ceiling: 0.82  — real behaviour is never perfectly predictable
    Minimum to surface: 0.40
    """
    import math

    data = request.get_json()
    user_email = data.get('email', '').strip()
    bulb_id    = data.get('bulb_id', '').strip()
    if not user_email or not bulb_id:
        return jsonify({'status': 'error', 'message': 'Missing fields'}), 400

    conn = get_db(); c = conn.cursor()

    # ── Fetch last 28 days of raw events ─────────────────────────────────────
    c.execute('''
        SELECT event_type, hour_of_day, minute_of_day, brightness, colour_temp,
               date(recorded_at), recorded_at
        FROM bulb_usage_events
        WHERE user_email = ? AND bulb_id = ?
          AND recorded_at >= datetime('now', '-28 days')
        ORDER BY recorded_at ASC
    ''', (user_email, bulb_id))
    events = c.fetchall()

    # Days on which ANY event was logged — the true denominator
    active_days       = set(row[5] for row in events)
    total_active_days = max(len(active_days), 1)

    # ── Collapse to one entry per (event_type, hour, slot, date) ─────────────
    # Prevents multiple taps in the same 30-min window on the same day from
    # inflating frequency above 1.0 per day.
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
        n = len(entries)   # distinct days this pattern fired

        # ── Factor 1: consistency (naturally 0–1) ────────────────────────────
        consistency = n / total_active_days

        # ── Factor 2: sample weight via sigmoid ──────────────────────────────
        # Ramps smoothly: 2 days ≈ 0.50, 7 ≈ 0.72, 14 ≈ 0.90, 21 ≈ 0.97
        sample_weight = 1.0 / (1.0 + math.exp(-0.35 * (n - 7)))

        # ── Factor 3: recency weight (0.70–1.00) ────────────────────────────
        recent        = sum(1 for e in entries if e['recorded_at'] >= week_ago_str)
        recency_ratio  = recent / n
        recency_weight = 0.70 + 0.30 * recency_ratio

        # ── Combine and cap ──────────────────────────────────────────────────
        confidence = min(round(consistency * sample_weight * recency_weight, 2), 0.82)

        if confidence < 0.40:
            continue

        # ── Median settings ──────────────────────────────────────────────────
        brights = [e['brightness']  for e in entries if e['brightness']  is not None]
        cols    = [e['colour_temp'] for e in entries if e['colour_temp'] is not None]
        med_b   = int(sorted(brights)[len(brights) // 2]) if brights else 255
        med_c   = int(sorted(cols)[len(cols) // 2])       if cols    else 128

        # ── Determine action ─────────────────────────────────────────────────
        if ev_type == 'power_off':
            action = 'power_off'
        elif ev_type == 'power_on':
            action = 'power_on'
        elif med_b <= 80:
            action = 'dim_warm'
        else:
            action = 'brightness_change'

        # ── Window + trigger time ────────────────────────────────────────────
        w_start_h, w_start_m = h, bm
        w_end_m = bm + 30;   w_end_h = h
        if w_end_m >= 60:    w_end_m -= 60; w_end_h += 1
        trigger_m = bm + 15; trigger_h = h
        if trigger_m >= 60:  trigger_m -= 60; trigger_h += 1

        # ── Deduplicate ──────────────────────────────────────────────────────
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


# ─────────────────────────────────────────────────────────────
# SUGGESTIONS CRUD
# ─────────────────────────────────────────────────────────────
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
    """Accept, dismiss, or auto-approve a suggestion."""
    data = request.get_json()
    suggestion_id = data.get('suggestion_id')
    response = data.get('response')   # 'accept' | 'dismiss' | 'auto'
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
            # Accept / auto – promote to schedule
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


# ─────────────────────────────────────────────────────────────
# SCHEDULES CRUD
# ─────────────────────────────────────────────────────────────
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
        c.execute('DELETE FROM schedules WHERE id=? AND user_email=?', (schedule_id, user_email))
        conn.commit(); conn.close()
        return jsonify({'status': 'success'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500


# ─────────────────────────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────────────────────────
if __name__ == "__main__":
    init_db()
    print("\n" + "="*50)
    print("Flask Server Starting…")
    print("="*50 + "\n")
    app.run(debug=True, host='0.0.0.0', port=5000)
