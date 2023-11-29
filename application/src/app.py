import platform
from flask import Flask, render_template

app = Flask(__name__, template_folder="/app/templates")


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
    return render_template('index.html', system_info=system_info)

if __name__ == '__main__':
    app.run(host="0.0.0.0", debug=True)