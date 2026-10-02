"""Serve simulator fixtures over HTTP so WebKit has real session history."""
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        url=urlparse(self.path)
        if url.path=='/health':
            body=b'ok'
        elif url.path.startswith('/external/'):
            name='A' if url.path.endswith('/a') else 'B'
            body=(f'<html><head><title>External {name}</title></head><body><h1>External {name}</h1><a href="/external/b">Next page</a></body></html>').encode()
        else:
            fixture='layout-fixture.html' if parse_qs(url.query).get('fixture')==['layout'] else 'navigation-fixture.html'
            if parse_qs(url.query).get('fixture')==['gestures']:fixture='gesture-fixture.html'
            if parse_qs(url.query).get('fixture')==['surfaces'] or url.path in ['/me','/profile/edit/basics','/profile/edit/about','/profile/edit/photos']:fixture='surface-fixture.html'
            body=Path(__file__).with_name(fixture).read_bytes()
        self.send_response(200)
        self.send_header('Content-Type','text/html; charset=utf-8')
        self.send_header('Content-Length',str(len(body)))
        self.end_headers()
        self.wfile.write(body)

HTTPServer(('127.0.0.1',18765),Handler).serve_forever()
