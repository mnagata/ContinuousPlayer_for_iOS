#!/usr/bin/env python3
"""Loopback-only DLNA fixture for restoration, delay, error and stall scenarios."""
import argparse
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import re
import time
from urllib.parse import urlsplit
from xml.etree import ElementTree as ET
from xml.sax.saxutils import escape


@dataclass
class Configuration:
    media: Path
    delay: float = 2
    stall_seconds: float = 35
    stall_after: int = 65536


def byte_range(header, size):
    if header is None:
        return 0, size - 1, 200
    match = re.fullmatch(r'bytes=(\d*)-(\d*)', header)
    if not match or not any(match.groups()):
        raise ValueError('unsupported range')
    first, last = match.groups()
    if not first:
        count = int(last)
        if count <= 0:
            raise ValueError('empty suffix')
        return max(0, size - count), size - 1, 206
    start = int(first)
    end = min(int(last) if last else size - 1, size - 1)
    if start >= size or start > end:
        raise ValueError('range outside resource')
    return start, end, 206


def container(identifier, title):
    return f'<container id="{identifier}"><dc:title>{escape(title)}</dc:title></container>'


def item(identifier, title, resource):
    return (f'<item id="{identifier}"><dc:title>{escape(title)}</dc:title>'
            f'<res protocolInfo="http-get:*:video/mp4:*">{escape(resource)}</res></item>')


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, format, *args):
        print(f'{self.command} {self.path} {format % args}', flush=True)

    def reply(self, data, status=200, mime='text/xml; charset=utf-8', extra=None):
        self.send_response(status)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(data)))
        for key, value in (extra or {}).items():
            self.send_header(key, value)
        self.end_headers()
        if self.command != 'HEAD':
            try:
                self.wfile.write(data)
            except (BrokenPipeError, ConnectionResetError):
                pass

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        path = urlsplit(self.path).path
        if path in ('/test/restore-missing', '/test/reset-missing'):
            self.server.missing_restored = path == '/test/restore-missing'
            self.reply(b'ok', mime='text/plain')
        elif path == '/media/missing.mp4' and getattr(self.server, 'missing_restored', False):
            self.serve_media('/media/op.mp4')
        elif path in ('/description.xml', '/desc/device.xml', '/slow-description.xml'):
            if path == '/slow-description.xml':
                time.sleep(self.server.config.delay)
            description = ('<root xmlns="urn:schemas-upnp-org:device-1-0"><device>'
                           '<deviceType>urn:schemas-upnp-org:device:MediaServer:1</deviceType>'
                           '<friendlyName>Common Spec Fixture</friendlyName><UDN>uuid:common-spec-fixture</UDN>'
                           '<serviceList><service><serviceType>urn:schemas-upnp-org:service:ContentDirectory:1</serviceType>'
                           '<controlURL>/control</controlURL></service></serviceList></device></root>')
            self.reply(description.encode())
        elif path == '/health':
            self.reply(json.dumps({'ready': True, 'delay': self.server.config.delay,
                                   'stall_seconds': self.server.config.stall_seconds}).encode(),
                       mime='application/json')
        elif path in ('/media/missing.mp4', '/media/unavailable.mp4'):
            self.reply(b'fixture failure', 404 if 'missing' in path else 503)
        elif path.startswith('/media/'):
            self.serve_media(path)
        else:
            self.reply(b'', 404)

    def serve_media(self, path):
        names = {'/media/op.mp4': 'Fixture OP.mp4', '/media/ed.mp4': 'Fixture ED.mp4',
                 '/media/slow.mp4': 'Fixture OP.mp4', '/media/stall.mp4': 'Fixture OP.mp4',
                 '/media/corrupt.mp4': 'Corrupt OP.mp4'}
        name = names.get(path)
        if not name:
            self.reply(b'', 404)
            return
        data = (self.server.config.media / name).read_bytes()
        try:
            start, end, status = byte_range(self.headers.get('Range'), len(data))
        except ValueError:
            self.reply(b'', 416, extra={'Content-Range': f'bytes */{len(data)}'})
            return
        if path == '/media/slow.mp4':
            time.sleep(self.server.config.delay)
        headers = {'Accept-Ranges': 'bytes'}
        if status == 206:
            headers['Content-Range'] = f'bytes {start}-{end}/{len(data)}'
        body = data[start:end + 1]
        if path != '/media/stall.mp4' or self.command == 'HEAD':
            self.reply(body, status, 'video/mp4', headers)
            return
        # Delay every range beyond this point too, preventing a new Range request
        # from silently bypassing the artificial network stall.
        split = max(0, min(len(body), self.server.config.stall_after - start))
        self.send_response(status)
        self.send_header('Content-Type', 'video/mp4')
        self.send_header('Content-Length', str(len(body)))
        for key, value in headers.items():
            self.send_header(key, value)
        self.end_headers()
        try:
            self.wfile.write(body[:split])
            self.wfile.flush()
            if split < len(body):
                time.sleep(self.server.config.stall_seconds)
                self.wfile.write(body[split:])
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_POST(self):
        if urlsplit(self.path).path != '/control':
            self.reply(b'', 404)
            return
        try:
            root = ET.fromstring(self.rfile.read(int(self.headers.get('Content-Length', '0'))))
            fields = {node.tag.split('}')[-1]: node.text for node in root.iter()}
            if fields.get('BrowseFlag') != 'BrowseDirectChildren':
                raise ValueError('expected BrowseDirectChildren')
            identifier = fields['ObjectID']
            start, count = int(fields.get('StartingIndex', '0')), int(fields.get('RequestedCount', '200'))
            if start < 0 or count < 0:
                raise ValueError('negative page')
        except (ET.ParseError, ValueError, KeyError):
            self.reply(b'invalid Browse request', 400)
            return
        if identifier == 'slow-list':
            time.sleep(self.server.config.delay)
        if identifier == '0':
            entries = [container(key, title) for key, title in [
                ('normal', 'Normal 90s'), ('slow-list', 'Slow listing'),
                ('slow-media', 'Slow preparation'), ('failure', 'Failures'), ('stall', 'Network stall')]]
        elif identifier in ('normal', 'slow-list'):
            entries = [item('op', 'Fixture OP.mp4', '/media/op.mp4'),
                       item('ed', 'Fixture ED.mp4', '/media/ed.mp4')]
        elif identifier == 'slow-media':
            entries = [item('slow', 'Slow OP.mp4', '/media/slow.mp4')]
        elif identifier == 'failure':
            entries = [item(key, title, '/media/' + key + '.mp4') for key, title in [
                ('corrupt', 'Corrupt OP.mp4'), ('missing', 'Missing OP.mp4'),
                ('unavailable', 'Unavailable OP.mp4'), ('op', 'Playable ED.mp4')]]
        elif identifier == 'stall':
            entries = [item('stall', 'Stall OP.mp4', '/media/stall.mp4')]
        else:
            self.reply(b'unknown ObjectID', 404)
            return
        page = entries[start:] if count == 0 else entries[start:start + count]
        didl = ('<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
                'xmlns:dc="http://purl.org/dc/elements/1.1/">' + ''.join(page) + '</DIDL-Lite>')
        response = ('<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
                    '<u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">'
                    f'<Result>{escape(didl)}</Result><NumberReturned>{len(page)}</NumberReturned>'
                    f'<TotalMatches>{len(entries)}</TotalMatches><UpdateID>1</UpdateID>'
                    '</u:BrowseResponse></s:Body></s:Envelope>')
        self.reply(response.encode())


def make_server(config, port=0):
    server = ThreadingHTTPServer(('127.0.0.1', port), Handler)
    server.daemon_threads = True
    server.config = config
    return server


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--media', type=Path, default=Path('validation/common-spec/media'))
    parser.add_argument('--port', type=int, default=18766)
    parser.add_argument('--delay', type=float, default=2)
    parser.add_argument('--stall-seconds', type=float, default=35)
    parser.add_argument('--ready-file', type=Path)
    args = parser.parse_args()
    if args.delay < 0 or args.stall_seconds < 0:
        parser.error('delays must be nonnegative')
    for name in ('Fixture OP.mp4', 'Fixture ED.mp4', 'Corrupt OP.mp4'):
        if not (args.media / name).is_file():
            parser.error('generate fixtures first: missing ' + name)
    with make_server(Configuration(args.media, args.delay, args.stall_seconds), args.port) as server:
        address = f'http://127.0.0.1:{server.server_port}'
        if args.ready_file:
            args.ready_file.write_text(address + '\n')
        print(f'Fixture ready: {address}/description.xml', flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == '__main__':
    main()
