#!/usr/bin/env python3
"""Exercise the fixture's HTTP behavior independently of the player implementation."""
import http.client
from pathlib import Path
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
from xml.etree import ElementTree as ET

from common_spec_fixture_server import Configuration, Handler, make_server


class FixtureServerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.temp.name)
        cls.media = bytes(range(256)) * 400
        for name in ('Fixture OP.mp4', 'Fixture ED.mp4', 'Corrupt OP.mp4'):
            (cls.root / name).write_bytes(cls.media if name != 'Corrupt OP.mp4' else b'bad media')
        cls.quiet = patch.object(Handler, 'log_message', lambda *args: None)
        cls.quiet.start()
        cls.server = make_server(Configuration(cls.root, delay=0.2, stall_seconds=0.2, stall_after=1024))
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()
        cls.quiet.stop()
        cls.temp.cleanup()

    def request(self, path, method='GET', headers=None, body=None):
        connection = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=3)
        try:
            connection.request(method, path, body=body, headers=headers or {})
            response = connection.getresponse()
            return response.status, dict(response.getheaders()), response.read()
        finally:
            connection.close()

    def browse(self, object_id, start=0, count=200):
        body = (f'<Browse><ObjectID>{object_id}</ObjectID><BrowseFlag>BrowseDirectChildren</BrowseFlag>'
                f'<StartingIndex>{start}</StartingIndex><RequestedCount>{count}</RequestedCount></Browse>')
        status, _, data = self.request('/control', 'POST', body=body)
        self.assertEqual(status, 200)
        response = ET.fromstring(data)
        fields = {node.tag.split('}')[-1]: node.text for node in response.iter()}
        return fields, ET.fromstring(fields['Result'])

    def test_description_and_health(self):
        status, _, body = self.request('/description.xml')
        self.assertEqual(status, 200)
        self.assertIn(b'Common Spec Fixture', body)
        ET.fromstring(body)
        self.assertEqual(self.request('/health')[0], 200)

    def test_range_and_head_contract(self):
        for value, start, end in [('bytes=20-29', 20, 29), ('bytes=20-', 20, len(self.media)-1),
                                  ('bytes=-10', len(self.media)-10, len(self.media)-1)]:
            with self.subTest(value=value):
                status, headers, body = self.request('/media/op.mp4', headers={'Range': value})
                self.assertEqual(status, 206)
                self.assertEqual(headers['Content-Range'], f'bytes {start}-{end}/{len(self.media)}')
                self.assertEqual(int(headers['Content-Length']), len(body))
                self.assertEqual(body, self.media[start:end+1])
        status, headers, body = self.request('/media/op.mp4', 'HEAD')
        self.assertEqual(status, 200)
        self.assertEqual(int(headers['Content-Length']), len(self.media))
        self.assertEqual(body, b'')

    def test_invalid_ranges_and_no_path_traversal(self):
        for value in ['bytes=999999-', 'bytes=30-20', 'bytes=-0', 'bytes=0-1,5-6', 'bytes=-']:
            self.assertEqual(self.request('/media/op.mp4', headers={'Range': value})[0], 416)
        self.assertEqual(self.request('/media/../manifest.json')[0], 404)

    def test_failures_and_playable_recovery(self):
        self.assertEqual(self.request('/media/missing.mp4')[0], 404)
        self.assertEqual(self.request('/media/unavailable.mp4')[0], 503)
        self.assertEqual(self.request('/media/corrupt.mp4')[2], b'bad media')
        self.assertEqual(self.request('/media/ed.mp4')[2], self.media)

    def test_browse_pages_and_delayed_listing(self):
        fields, entries = self.browse('0', start=1, count=2)
        self.assertEqual(fields['TotalMatches'], '5')
        self.assertEqual(fields['NumberReturned'], '2')
        self.assertEqual([node.attrib['id'] for node in entries], ['slow-list', 'slow-media'])
        begin = time.monotonic()
        _, entries = self.browse('slow-list')
        self.assertGreaterEqual(time.monotonic() - begin, 0.15)
        self.assertEqual([node.attrib['id'] for node in entries], ['op', 'ed'])

    def test_preparation_delay_and_stall_cannot_be_bypassed_by_range(self):
        for path, headers in [('/media/slow.mp4', {}),
                              ('/media/stall.mp4', {}),
                              ('/media/stall.mp4', {'Range': 'bytes=2048-4095'})]:
            with self.subTest(path=path, headers=headers):
                begin = time.monotonic()
                status, _, body = self.request(path, headers=headers)
                self.assertIn(status, (200, 206))
                self.assertGreaterEqual(time.monotonic() - begin, 0.15)
                self.assertEqual(body, self.media[2048:4096] if headers else self.media)

    def test_cancelled_slow_request_does_not_block_other_requests(self):
        connection = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=0.03)
        try:
            connection.request('GET', '/media/slow.mp4')
            with self.assertRaises(TimeoutError):
                connection.getresponse()
        finally:
            connection.close()
        self.assertEqual(self.request('/health')[0], 200)
        # Let the cancelled writer exercise its broken-pipe path before teardown.
        time.sleep(0.25)


if __name__ == '__main__':
    unittest.main(verbosity=2)
