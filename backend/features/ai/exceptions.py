from fastapi import HTTPException, status

class AIJobNotFoundException(HTTPException):
    def __init__(self, job_id: str):
        super().__init__(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"AI job with ID {job_id} not found."
        )

class RecommendationNotFoundException(HTTPException):
    def __init__(self, rec_id: str):
        super().__init__(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Recommendation with ID {rec_id} not found."
        )

class AIProcessingException(HTTPException):
    def __init__(self, message: str):
        super().__init__(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=message
        )
