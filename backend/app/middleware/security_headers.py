from starlette.middleware.base import BaseHTTPMiddleware
from fastapi import Request, Response
from typing import Type

class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        response = await call_next(request)
        
        # Prevent clickjacking by restricting framing
        response.headers["X-Frame-Options"] = "DENY"
        
        # Disable MIME sniffing
        response.headers["X-Content-Type-Options"] = "nosniff"
        
        # Enable XSS protection in modern browsers
        response.headers["X-XSS-Protection"] = "1; mode=block"
        
        # Referrer Policy
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        
        # Content Security Policy (CSP) supporting CDN resources and local assets
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; "
            "script-src 'self' 'unsafe-inline' 'unsafe-eval' https://cdn.jsdelivr.net; "
            "style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; "
            "img-src 'self' data: blob: android-webview-video-poster:; "
            "connect-src 'self' *; "
            "font-src 'self' https://fonts.gstatic.com;"
        )
        
        return response
