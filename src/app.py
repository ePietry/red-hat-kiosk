import platform
from flask import Flask, render_template

app = Flask(__name__)

@app.route('/')
def system_info():
    system_info = {
        'System': platform.system(),
        'Node Name': platform.node(),
        'Release': platform.release(),
        'Version': platform.version(),
        'Machine': platform.machine(),
        'Processor': platform.processor()
    }
    return render_template('system_info.html', system_info=system_info)

if __name__ == '__main__':
    app.run(debug=True)