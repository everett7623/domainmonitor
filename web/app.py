from flask import Flask, render_template, g
import sqlite3
import os

app = Flask(__name__)
DATABASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'db/history.db')

def get_db():
    db = getattr(g, '_database', None)
    if db is None:
        db = g._database = sqlite3.connect(DATABASE)
        db.row_factory = sqlite3.Row
    return db

@app.teardown_appcontext
def close_connection(exception):
    db = getattr(g, '_database', None)
    if db is not None:
        db.close()

@app.route('/')
def index():
    cursor = get_db().cursor()
    cursor.execute("SELECT * FROM history ORDER BY check_time DESC LIMIT 100")
    history_logs = cursor.fetchall()
    return render_template('index.html', logs=history_logs)

if __name__ == '__main__':
    # 生产环境建议使用 Gunicorn 等 WSGI 服务器
    app.run(host='0.0.0.0', port=5000)
