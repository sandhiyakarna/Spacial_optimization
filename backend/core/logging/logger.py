import logging
import sys
import os
from logging.handlers import RotatingFileHandler

def setup_logging(log_level: str = "INFO") -> logging.Logger:
    logger = logging.getLogger("flowspace")
    logger.setLevel(log_level.upper())
    
    # Avoid duplicate handlers if setup multiple times
    if not logger.handlers:
        formatter = logging.Formatter(
            "[%(asctime)s] %(levelname)s [%(name)s:%(lineno)s] %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S"
        )
        
        # Stream Handler to stdout
        stdout_handler = logging.StreamHandler(sys.stdout)
        stdout_handler.setFormatter(formatter)
        logger.addHandler(stdout_handler)
        
        # File Handler for App logs
        try:
            # core/logging/logger.py -> core -> backend root
            base_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
            logs_dir = os.path.join(base_dir, "logs")
            os.makedirs(logs_dir, exist_ok=True)
            log_file = os.path.join(logs_dir, "flowspace.log")
            
            # Rotating file handler (10MB max, keep 5 backups)
            file_handler = RotatingFileHandler(
                log_file, maxBytes=10 * 1024 * 1024, backupCount=5, encoding="utf-8"
            )
            file_handler.setFormatter(formatter)
            logger.addHandler(file_handler)
        except Exception as e:
            # Fallback if logs directory cannot be created or file cannot be opened
            logger.error(f"Failed to setup file logging: {e}")
            
    return logger

# Load logging level dynamically from environment
log_level = os.getenv("LOG_LEVEL", "INFO")
logger = setup_logging(log_level)
