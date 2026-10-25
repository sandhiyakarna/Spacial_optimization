from pydantic import BaseModel
from typing import List, Dict, Optional
from datetime import datetime

class StorageSubdirInfo(BaseModel):
    name: str
    count: int
    size_bytes: int
    size_formatted: str

class DiskUsageInfo(BaseModel):
    total: int
    free: int
    used: int
    percent_used: float

class StorageOverview(BaseModel):
    total_files: int
    total_size_bytes: int
    total_size_formatted: str
    subdirectories: List[StorageSubdirInfo]
    disk_usage: DiskUsageInfo

class DatabaseStatus(BaseModel):
    connected: bool
    type: str
    file_size_bytes: int
    file_size_formatted: str
    table_counts: Dict[str, int]

class BackupFileInfo(BaseModel):
    filename: str
    size_bytes: int
    size_formatted: str
    created_at: str

class BackupStatus(BaseModel):
    backups_dir: str
    backup_files: List[BackupFileInfo]
    last_backup: Optional[str] = None

class HealthCheckDetail(BaseModel):
    service: str
    status: str
    message: Optional[str] = None

class EnvironmentInfo(BaseModel):
    environment: str
    python_version: str
    os: str
    fastapi_version: str
    sqlalchemy_version: str
    settings: Dict[str, str]

class CacheStatus(BaseModel):
    cache_dir: str
    size_bytes: int
    size_formatted: str
    files_count: int

class SystemOverviewResponse(BaseModel):
    health: List[HealthCheckDetail]
    storage: StorageOverview
    database: DatabaseStatus
    backup: BackupStatus
    environment: EnvironmentInfo
    cache: CacheStatus

class LogsResponse(BaseModel):
    logs: List[str]
    count: int

class BackupCreateResponse(BaseModel):
    success: bool
    message: str
    filename: str

class CachePurgeResponse(BaseModel):
    success: bool
    message: str
    previous_size: str
    current_size: str

class EndpointMetric(BaseModel):
    count: int
    total_latency: float
    average_latency_ms: float
    errors: int

class SystemMetricsResponse(BaseModel):
    uptime_seconds: float
    total_requests: int
    active_requests: int
    error_requests: int
    error_rate_percent: float
    average_latency_ms: float
    status_code_distribution: Dict[int, int]
    endpoints: Dict[str, EndpointMetric]
