"""Loopback-only UPnP/HTTP fixture; never contacts a NAS or requires multicast."""
import http.server
import os
import sys
import time
import wave
import xml.etree.ElementTree as ET
from pathlib import Path
from xml.sax.saxutils import escape
from urllib.parse import urlparse, parse_qs

output = Path(sys.argv[1])
media = Path(sys.argv[2]) if len(sys.argv) > 2 else output / 'media.wav'
if len(sys.argv) <= 2:
    with wave.open(str(media), 'wb') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(8000)
        f.writeframes(b'\0\0' * 4000)


def item(identifier, mime='video/mp4'):
    return f'<item id="{identifier}"><dc:title>作品 {identifier.upper()}.mp4</dc:title><res protocolInfo="http-get:*:{mime}:*" size="1234">/stream?id={identifier}</res></item>'


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *args):
        pass

    def reply(self, data, status=200, mime='text/xml; charset=utf-8', extra=None):
        self.send_response(status)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(data)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != 'HEAD':
            try:
                self.wfile.write(data)
            except (BrokenPipeError, ConnectionResetError):
                pass

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        if urlparse(self.path).path in ('/description.xml', '/desc/device.xml'):
            text = '<root xmlns="urn:schemas-upnp-org:device-1-0"><device><deviceType>urn:schemas-upnp-org:device:MediaServer:1</deviceType><friendlyName>Fixture NAS</friendlyName><UDN>uuid:fixture</UDN><serviceList><service><serviceType>urn:schemas-upnp-org:service:ContentDirectory:1</serviceType><controlURL>/control</controlURL></service></serviceList></device></root>'
            self.reply(text.encode())
        elif urlparse(self.path).path == '/management':
            self.reply(b'<html><body>DSM login</body></html>', mime='text/html')
        elif urlparse(self.path).path == '/denied':
            self.reply(b'Forbidden', 403)
        elif urlparse(self.path).path == '/unavailable':
            self.reply(b'Unavailable', 503)
        elif urlparse(self.path).path == '/stream':
            data = media.read_bytes()
            mime = 'video/mp4' if media.suffix in ('.mp4', '.m4v') else 'audio/wav'
            size = len(data)
            if self.headers.get('Range', '').startswith('bytes='):
                start, end = self.headers['Range'][6:].split('-', 1)
                start, end = int(start or 0), min(int(end) if end else size - 1, size - 1)
                if start >= size:
                    self.reply(b'', 416, extra={'Content-Range': f'bytes */{size}'})
                    return
                self.reply(data[start:end + 1], 206, mime, {'Content-Range': f'bytes {start}-{end}/{size}', 'Accept-Ranges': 'bytes'})
            else:
                self.reply(data, mime=mime, extra={'Accept-Ranges': 'bytes'})
        else:
            self.reply(b'', 404)

    def do_POST(self):
        body = self.rfile.read(int(self.headers['Content-Length']))
        assert self.headers['SOAPAction'] == '"urn:schemas-upnp-org:service:ContentDirectory:1#Browse"'
        root = ET.fromstring(body)
        fields = {node.tag.split('}')[-1]: node.text for node in root.iter()}
        identifier = fields['ObjectID']
        start = int(fields['StartingIndex'])
        assert fields['BrowseFlag'] == 'BrowseDirectChildren'
        if identifier == 'slow':
            time.sleep(2)
        if identifier == 'http-error':
            self.reply(b'Unavailable', 503)
            return
        if identifier == 'malformed':
            self.reply(b'<broken>')
            return
        if identifier == 'fault':
            self.reply(b'<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault><faultstring>UPnPError</faultstring><detail><UPnPError><errorDescription>No Such Object</errorDescription></UPnPError></detail></s:Fault></s:Body></s:Envelope>', 500)
            return
        update = 2 if identifier == 'changed' and start else 1
        if identifier == 'empty':
            content, returned, total = '', 0, 0
        elif identifier == 'truncated':
            content, returned, total = '', 0, 2
        elif identifier == 'repeat':
            content, returned, total = item('op'), 1, 3
        elif start == 0:
            content, returned, total = item('unsupported', 'video/x-matroska') + item('op'), 2, 3
        else:
            assert start == 2, 'StartingIndex must include unsupported entries'
            content, returned, total = item('ed'), 1, 3
        didl = '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/">' + content + '</DIDL-Lite>'
        text = f'<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1"><Result>{escape(didl)}</Result><NumberReturned>{returned}</NumberReturned><TotalMatches>{total}</TotalMatches><UpdateID>{update}</UpdateID></u:BrowseResponse></s:Body></s:Envelope>'
        self.reply(text.encode())


server = http.server.ThreadingHTTPServer(('127.0.0.1', int(os.environ.get('DLNA_FIXTURE_PORT', '0'))), Handler)
(output / 'port').write_text(str(server.server_port))
server.serve_forever()
