from fastapi import Request, Response, status
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError, HTTPException
from sqlalchemy.exc import SQLAlchemyError, OperationalError, InterfaceError
from starlette.middleware.base import BaseHTTPMiddleware
from core.logging.logger import logger
import traceback

class GlobalExceptionMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        try:
            response = await call_next(request)
            return response
        except HTTPException as exc:
            logger.error(f"HTTPException: status_code={exc.status_code} detail={exc.detail}")
            return JSONResponse(
                status_code=exc.status_code,
                content={
                    "detail": exc.detail,
                    "error_code": "HTTP_EXCEPTION",
                    "status_code": exc.status_code
                }
            )
        except RequestValidationError as exc:
            logger.error(f"ValidationError: errors={exc.errors()}")
            return JSONResponse(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                content={
                    "detail": "Request validation failed",
                    "errors": exc.errors(),
                    "error_code": "VALIDATION_ERROR",
                    "status_code": status.HTTP_422_UNPROCESSABLE_ENTITY
                }
            )
        except (OperationalError, InterfaceError) as exc:
            logger.critical(f"DatabaseConnectionError: {exc}\n{traceback.format_exc()}")
            return JSONResponse(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                content={
                    "detail": "Database service is temporarily unavailable. Please try again later.",
                    "error_code": "DATABASE_CONNECTION_ERROR",
                    "status_code": status.HTTP_503_SERVICE_UNAVAILABLE
                }
            )
        except SQLAlchemyError as exc:
            logger.critical(f"DatabaseError: {exc}\n{traceback.format_exc()}")
            return JSONResponse(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                content={
                    "detail": "A database error occurred.",
                    "error_code": "DATABASE_ERROR",
                    "status_code": status.HTTP_500_INTERNAL_SERVER_ERROR
                }
            )
        except Exception as exc:
            logger.critical(f"UnhandledException: {exc}\n{traceback.format_exc()}")
            return JSONResponse(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                content={
                    "detail": "An internal server error occurred.",
                    "error_code": "INTERNAL_SERVER_ERROR",
                    "status_code": status.HTTP_500_INTERNAL_SERVER_ERROR
                }
            )
