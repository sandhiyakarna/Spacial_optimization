from pydantic import BaseModel, EmailStr, Field, field_validator
from typing import Optional, Any

def validate_password_strength(password: str) -> str:
    if len(password) < 8:
        raise ValueError("Password must be at least 8 characters long")
    if not any(c.isupper() for c in password):
        raise ValueError("Password must include at least one uppercase letter")
    if not any(c.islower() for c in password):
        raise ValueError("Password must include at least one lowercase letter")
    if not any(c.isdigit() for c in password):
        raise ValueError("Password must include at least one number")
    
    special_chars = "!@#$%^&*()_+-=[]{}|;':\",./<>?`~"
    if not any(c in special_chars for c in password):
        raise ValueError("Password must include at least one special character")
    return password

# Auth Requests
class UserRegister(BaseModel):
    full_name: str = Field(..., min_length=1, max_length=100)
    email: EmailStr
    password: str = Field(..., min_length=8)

    @field_validator("password")
    @classmethod
    def validate_password(cls, v: str) -> str:
        return validate_password_strength(v)

    @field_validator("email")
    @classmethod
    def clean_email(cls, v: str) -> str:
        return v.strip().lower()

    @field_validator("full_name")
    @classmethod
    def clean_name(cls, v: str) -> str:
        return v.strip()

class UserLogin(BaseModel):
    email: EmailStr
    password: str
    remember_me: Optional[bool] = False

    @field_validator("email")
    @classmethod
    def clean_email(cls, v: str) -> str:
        return v.strip().lower()

class VerifyEmailRequest(BaseModel):
    token: str

class RefreshTokenRequest(BaseModel):
    refresh_token: str

class UpdateProfileRequest(BaseModel):
    full_name: str = Field(..., min_length=1, max_length=100)
    profile_image: Optional[str] = None

    @field_validator("full_name")
    @classmethod
    def clean_name(cls, v: str) -> str:
        return v.strip()

class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str = Field(..., min_length=8)

    @field_validator("new_password")
    @classmethod
    def validate_new_password(cls, v: str) -> str:
        return validate_password_strength(v)

class ForgotPasswordRequest(BaseModel):
    email: EmailStr

    @field_validator("email")
    @classmethod
    def clean_email(cls, v: str) -> str:
        return v.strip().lower()

class ResetPasswordRequest(BaseModel):
    token: str
    new_password: str = Field(..., min_length=8)

    @field_validator("new_password")
    @classmethod
    def validate_new_password(cls, v: str) -> str:
        return validate_password_strength(v)

class DeleteAccountRequest(BaseModel):
    password: str

# Auth Responses
class ResponseModel(BaseModel):
    success: bool
    message: str
    data: Optional[Any] = None

class TokenData(BaseModel):
    access_token: str
    refresh_token: str
    expires_in: int = 3600

class TokenResponse(BaseModel):
    success: bool
    message: str
    data: TokenData

class ProfileData(BaseModel):
    id: str
    full_name: str
    email: str
    profile_image: Optional[str] = None
    role: str
    theme: str
    language: str
    measurement_unit: str
    default_room_unit: str
    notifications_enabled: bool
    is_verified: bool

class ProfileResponse(BaseModel):
    success: bool
    data: ProfileData


# User Management Schemas
from datetime import datetime
from typing import List

class AdminUserResponse(BaseModel):
    id: str
    full_name: str
    email: str
    role: str
    is_active: bool
    is_verified: bool
    last_login: Optional[datetime] = None
    created_at: datetime

class PermissionResponse(BaseModel):
    id: str
    name: str
    description: Optional[str] = None
    created_at: datetime

class RoleResponse(BaseModel):
    id: str
    name: str
    description: Optional[str] = None
    created_at: datetime
    permissions: List[PermissionResponse]

class UserRoleUpdate(BaseModel):
    role_name: str

class RolePermissionsUpdate(BaseModel):
    permission_names: List[str]

class UserSessionResponse(BaseModel):
    id: str
    is_active: bool
    expires_at: datetime
    created_at: datetime
    access_token_masked: str
    refresh_token_masked: str
