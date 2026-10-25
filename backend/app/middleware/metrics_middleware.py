import time
from starlette.middleware.base import BaseHTTPMiddleware
from fastapi import Request, Response
from core.monitoring.metrics import metrics_manager
from core.logging.logger import logger

class RequestMetricsMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        # Ignore paths that are not API requests to avoid polluting endpoint logs
        # but feel free to track or skip based on pattern. We track /api and /health.
        path = request.url.path
        method = request.method
        
        # Don't track static files or uploads to avoid inflating endpoint metrics
        is_static_or_upload = path.startswith("/static") or path.startswith("/uploads")
        
        if is_static_or_upload:
            return await call_next(request)
            
        metrics_manager.record_request_start()
        start_time = time.time()
        
        try:
            response = await call_next(request)
            duration = time.time() - start_time
            metrics_manager.record_request_end(method, path, response.status_code, duration)
            return response
        except Exception as e:
            # In case of an unhandled exception before GlobalExceptionMiddleware runs
            duration = time.time() - start_time
            metrics_manager.record_request_end(method, path, 500, duration)
            raise e
