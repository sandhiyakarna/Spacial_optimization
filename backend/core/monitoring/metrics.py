import threading
import time
from typing import Dict, Any, List

class MetricsManager:
    def __init__(self):
        self._lock = threading.Lock()
        self.total_requests = 0
        self.active_requests = 0
        self.error_requests = 0  # 5xx responses
        self.status_codes: Dict[int, int] = {}
        self.total_latency = 0.0
        self.endpoints: Dict[str, Dict[str, Any]] = {}
        self.start_time = time.time()

    def record_request_start(self):
        with self._lock:
            self.total_requests += 1
            self.active_requests += 1

    def record_request_end(self, method: str, path: str, status_code: int, latency: float):
        with self._lock:
            if self.active_requests > 0:
                self.active_requests -= 1
            
            # Status code distribution
            self.status_codes[status_code] = self.status_codes.get(status_code, 0) + 1
            
            # Error tracking (5xx status codes)
            if 500 <= status_code < 600:
                self.error_requests += 1
                
            # Latency tracking
            self.total_latency += latency
            
            # Per-endpoint tracking
            # Normalize path (e.g. remove query strings or format ID parameters in a simple way if needed,
            # but standard method + path is fine for basic tracking)
            key = f"{method} {path}"
            if key not in self.endpoints:
                self.endpoints[key] = {
                    "count": 0,
                    "total_latency": 0.0,
                    "average_latency_ms": 0.0,
                    "errors": 0
                }
                
            self.endpoints[key]["count"] += 1
            self.endpoints[key]["total_latency"] += latency
            self.endpoints[key]["average_latency_ms"] = round(
                (self.endpoints[key]["total_latency"] / self.endpoints[key]["count"]) * 1000, 2
            )
            if 500 <= status_code < 600:
                self.endpoints[key]["errors"] += 1

    def get_summary(self) -> Dict[str, Any]:
        with self._lock:
            uptime = time.time() - self.start_time
            avg_latency = (
                round((self.total_latency / self.total_requests) * 1000, 2)
                if self.total_requests > 0
                else 0.0
            )
            error_rate = (
                round((self.error_requests / self.total_requests) * 100, 2)
                if self.total_requests > 0
                else 0.0
            )
            
            return {
                "uptime_seconds": round(uptime, 2),
                "total_requests": self.total_requests,
                "active_requests": self.active_requests,
                "error_requests": self.error_requests,
                "error_rate_percent": error_rate,
                "average_latency_ms": avg_latency,
                "status_code_distribution": self.status_codes.copy(),
                "endpoints": {k: v.copy() for k, v in self.endpoints.items()}
            }

    def reset(self):
        with self._lock:
            self.total_requests = 0
            self.active_requests = 0
            self.error_requests = 0
            self.status_codes.clear()
            self.total_latency = 0.0
            self.endpoints.clear()
            self.start_time = time.time()

# Global metrics manager instance
metrics_manager = MetricsManager()
