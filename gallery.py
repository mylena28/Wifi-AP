import os
import sys
from flask import Flask, send_file, abort, Response, redirect, request

app = Flask(__name__)

BASE = os.environ.get("IMAGE_DIR") or (sys.argv[1] if len(sys.argv) > 1 else ".")
BASE = os.path.realpath(BASE)

NETWORKS_FILE = "/etc/wifi_manager/networks.conf"
AP_SUBNET = "192.168.50."

IMAGE_EXT = {".jpg", ".jpeg", ".png", ".bmp", ".gif", ".webp"}


def _only_ap(f):
    """Bloqueia acesso à página de redes fora da rede AP."""
    from functools import wraps
    @wraps(f)
    def wrapper(*args, **kwargs):
        if not request.remote_addr.startswith(AP_SUBNET):
            return Response("Disponível apenas via Wi-Fi AP (PiGaleria).", status=403)
        return f(*args, **kwargs)
    return wrapper


def _read_networks():
    nets = []
    if not os.path.isfile(NETWORKS_FILE):
        return nets
    with open(NETWORKS_FILE) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                ssid, _, password = line.partition("=")
                nets.append((ssid.strip(), password.strip()))
    return nets


def _write_networks(nets):
    header = (
        "# Redes Wi-Fi conhecidas — uma por linha\n"
        "# Formato: SSID=senha  |  Rede aberta: SSID=\n"
        "# Linhas com # são ignoradas.\n\n"
    )
    with open(NETWORKS_FILE, "w") as f:
        f.write(header)
        for ssid, password in nets:
            f.write(f"{ssid}={password}\n")


REDES_HEAD = """<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Gerenciar Redes</title>
  <style>
    body { font-family: sans-serif; margin: 0; padding: 16px; background: #111; color: #eee; max-width: 480px; }
    h2 { font-size: 1.1rem; margin-bottom: 16px; }
    a { color: #7bf; text-decoration: none; }
    .back { display:inline-block; margin-bottom:16px; padding:6px 12px; background:#333; border-radius:4px; }
    table { width: 100%; border-collapse: collapse; margin-bottom: 24px; }
    td, th { padding: 8px 6px; border-bottom: 1px solid #333; font-size: 0.9rem; text-align: left; }
    th { color: #aaa; font-weight: normal; }
    .ssid { word-break: break-all; }
    .pass { color: #888; font-size: 0.8rem; word-break: break-all; }
    .btn-rm { background: #522; color: #faa; border: none; border-radius: 4px;
              padding: 4px 10px; cursor: pointer; font-size: 0.8rem; }
    fieldset { border: 1px solid #444; border-radius: 6px; padding: 12px; }
    legend { color: #aaa; font-size: 0.85rem; padding: 0 6px; }
    input { width: 100%; box-sizing: border-box; background: #222; border: 1px solid #555;
            color: #eee; padding: 7px 8px; border-radius: 4px; margin-top: 6px; font-size: 0.9rem; }
    .btn-add { margin-top: 12px; background: #253; color: #afa; border: none; border-radius: 4px;
               padding: 8px 16px; cursor: pointer; font-size: 0.9rem; width: 100%; }
    .empty { color: #666; font-style: italic; padding: 8px 0; }
  </style>
</head>
<body>"""


@app.route("/redes")
@_only_ap
def redes_page():
    nets = _read_networks()

    rows = ""
    if nets:
        for ssid, password in nets:
            masked = ("*" * min(len(password), 8)) if password else "(aberta)"
            rows += (
                f"<tr>"
                f"<td class='ssid'>{ssid}</td>"
                f"<td class='pass'>{masked}</td>"
                f"<td><form method='post' action='/redes/remover' style='margin:0'>"
                f"<input type='hidden' name='ssid' value='{ssid}'>"
                f"<button class='btn-rm' type='submit'>remover</button></form></td>"
                f"</tr>"
            )
    else:
        rows = "<tr><td colspan='3' class='empty'>Nenhuma rede cadastrada.</td></tr>"

    html = (
        REDES_HEAD
        + "<a class='back' href='/'>&#8592; Galeria</a>"
        + "<h2>Redes Wi-Fi conhecidas</h2>"
        + "<table><tr><th>SSID</th><th>Senha</th><th></th></tr>"
        + rows
        + "</table>"
        + "<fieldset><legend>Adicionar rede</legend>"
        + "<form method='post' action='/redes/adicionar'>"
        + "<input name='ssid' placeholder='Nome da rede (SSID)' required>"
        + "<input name='password' placeholder='Senha (deixe vazio para rede aberta)'>"
        + "<button class='btn-add' type='submit'>+ Adicionar</button>"
        + "</form></fieldset>"
        + "</body></html>"
    )
    return Response(html, mimetype="text/html")


@app.route("/redes/adicionar", methods=["POST"])
@_only_ap
def redes_add():
    ssid = request.form.get("ssid", "").strip()
    password = request.form.get("password", "").strip()
    if not ssid:
        abort(400)
    nets = [(s, p) for s, p in _read_networks() if s != ssid]
    nets.append((ssid, password))
    _write_networks(nets)
    return redirect("/redes")


@app.route("/redes/remover", methods=["POST"])
@_only_ap
def redes_remove():
    ssid = request.form.get("ssid", "").strip()
    nets = [(s, p) for s, p in _read_networks() if s != ssid]
    _write_networks(nets)
    return redirect("/redes")


HTML_HEAD = """
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Gallery</title>
  <style>
    body { font-family: sans-serif; margin: 0; padding: 12px; background: #111; color: #eee; }
    h2 { font-size: 1rem; word-break: break-all; margin-bottom: 12px; }
    a { color: #7bf; text-decoration: none; }
    .grid { display: flex; flex-wrap: wrap; gap: 10px; }
    .img-card { text-align: center; font-size: 0.75rem; max-width: 160px; }
    .img-card img { width: 150px; height: 110px; object-fit: cover;
                    border-radius: 6px; border: 1px solid #444; }
    .dir-list { list-style: none; padding: 0; margin-bottom: 16px; }
    .dir-list li { padding: 6px 0; border-bottom: 1px solid #333; }
    .back { display: inline-block; margin-bottom: 12px;
            padding: 6px 12px; background: #333; border-radius: 4px; }
  </style>
</head>
<body>
"""

@app.route("/", defaults={"subpath": ""})
@app.route("/<path:subpath>")
def browse(subpath):
    full_path = os.path.realpath(os.path.join(BASE, subpath))

    # prevent path traversal outside BASE
    if not full_path.startswith(BASE):
        abort(403)

    if os.path.isfile(full_path):
        return send_file(full_path)

    if not os.path.isdir(full_path):
        abort(404)

    entries = sorted(os.listdir(full_path))
    dirs = [e for e in entries if os.path.isdir(os.path.join(full_path, e))]
    images = [e for e in entries if os.path.splitext(e)[1].lower() in IMAGE_EXT]
    others = [e for e in entries
              if e not in dirs and os.path.splitext(e)[1].lower() not in IMAGE_EXT]

    def href(name):
        return ("/" + subpath + "/" + name).replace("//", "/")

    redes_link = ""
    if request.remote_addr.startswith(AP_SUBNET):
        redes_link = '<a style="float:right;font-size:0.8rem;color:#aaa" href="/redes">⚙ redes wi-fi</a>'

    parts = [HTML_HEAD, f"{redes_link}<h2>/{subpath or ''}</h2>"]

    if subpath:
        parent = "/".join(subpath.rstrip("/").split("/")[:-1])
        parts.append(f'<a class="back" href="/{parent}">&#8592; Back</a>')

    if dirs:
        parts.append("<ul class='dir-list'>")
        for d in dirs:
            parts.append(f'<li>&#128193; <a href="{href(d)}">{d}/</a></li>')
        parts.append("</ul>")

    if others:
        parts.append("<ul class='dir-list'>")
        for f in others:
            parts.append(f'<li>&#128196; <a href="{href(f)}">{f}</a></li>')
        parts.append("</ul>")

    if images:
        parts.append("<div class='grid'>")
        for img in images:
            parts.append(
                f'<div class="img-card">'
                f'<a href="{href(img)}">'
                f'<img src="{href(img)}" loading="lazy"/>'
                f'</a><br>{img}</div>'
            )
        parts.append("</div>")

    if not dirs and not images and not others:
        parts.append("<p>Empty folder.</p>")

    parts.append("</body></html>")
    return Response("".join(parts), mimetype="text/html")


# Android network validation probe — returns 204 so Android stops cycling BT PAN
@app.route("/generate_204")
def generate_204():
    return Response(status=204)


if __name__ == "__main__":
    print(f"[GALLERY] Base folder: {BASE}")
    app.run(host="0.0.0.0", port=8080, debug=False)
