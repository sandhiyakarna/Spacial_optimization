from fastapi import APIRouter, Depends, status, Request, HTTPException
from sqlalchemy.orm import Session
from app.dependencies import get_db, get_current_user, security
from features.auth.schemas import (
    UserRegister, UserLogin, RefreshTokenRequest, UpdateProfileRequest,
    ChangePasswordRequest, ForgotPasswordRequest, ResetPasswordRequest, DeleteAccountRequest,
    ResponseModel, TokenResponse, ProfileResponse, ProfileData, TokenData, VerifyEmailRequest
)
from features.auth.services import AuthService
from features.auth.models import User

router = APIRouter(prefix="/auth", tags=["Authentication"])

@router.post("/register", response_model=ResponseModel, status_code=status.HTTP_201_CREATED)
def register(user_data: UserRegister, db: Session = Depends(get_db)):
    user = AuthService.register_user(db, user_data)
    return ResponseModel(
        success=True,
        message="User registered successfully.",
        data={"user_id": user.id}
    )

@router.post("/login", response_model=TokenResponse)
def login(login_data: UserLogin, request: Request, db: Session = Depends(get_db)):
    ip_address = request.client.host if request.client else None
    token_info = AuthService.login_user(db, login_data, ip_address=ip_address)
    return TokenResponse(
        success=True,
        message="Login successful.",
        data=TokenData(
            access_token=token_info["access_token"],
            refresh_token=token_info["refresh_token"],
            expires_in=token_info["expires_in"]
        )
    )

@router.post("/refresh", response_model=ResponseModel)
def refresh(refresh_data: RefreshTokenRequest, db: Session = Depends(get_db)):
    new_access_token = AuthService.refresh_session_token(db, refresh_data.refresh_token)
    return ResponseModel(
        success=True,
        message="Token refreshed successfully.",
        data={"access_token": new_access_token}
    )

@router.post("/logout", response_model=ResponseModel)
def logout(credentials = Depends(security), db: Session = Depends(get_db)):
    token = credentials.credentials
    AuthService.logout_user(db, token)
    return ResponseModel(
        success=True,
        message="Logged out successfully."
    )

@router.get("/profile", response_model=ProfileResponse)
def get_profile(current_user: User = Depends(get_current_user)):
    return ProfileResponse(
        success=True,
        data=ProfileData(
            id=current_user.id,
            full_name=current_user.full_name,
            email=current_user.email,
            profile_image=current_user.profile_image,
            role=current_user.role.name,
            theme=current_user.preferences.theme if current_user.preferences else "System",
            language=current_user.preferences.language if current_user.preferences else "English",
            measurement_unit=current_user.preferences.measurement_unit if current_user.preferences else "Centimeters",
            default_room_unit=current_user.preferences.default_room_unit if current_user.preferences else "Centimeters",
            notifications_enabled=current_user.preferences.notifications_enabled if current_user.preferences else True,
            is_verified=current_user.is_verified
        )
    )

@router.put("/profile", response_model=ResponseModel)
def update_profile(
    profile_data: UpdateProfileRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    current_user.full_name = profile_data.full_name
    if profile_data.profile_image is not None:
        current_user.profile_image = profile_data.profile_image
    db.commit()
    return ResponseModel(
        success=True,
        message="Profile updated successfully."
    )

@router.put("/change-password", response_model=ResponseModel)
def change_password(
    pwd_data: ChangePasswordRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    from core.security.jwt import verify_password, hash_password
    # Verify current password
    if not verify_password(pwd_data.current_password, current_user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Current password must match"
        )
    
    if pwd_data.current_password == pwd_data.new_password:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="New password must differ from current password"
        )
        
    current_user.password_hash = hash_password(pwd_data.new_password)
    db.commit()
    return ResponseModel(
        success=True,
        message="Password updated successfully."
    )

@router.post("/forgot-password", response_model=ResponseModel)
def forgot_password(forgot_data: ForgotPasswordRequest, db: Session = Depends(get_db)):
    AuthService.forgot_password_request(db, forgot_data.email)
    return ResponseModel(
        success=True,
        message="If an account exists, password reset instructions have been sent."
    )

@router.post("/reset-password", response_model=ResponseModel)
def reset_password(reset_data: ResetPasswordRequest, db: Session = Depends(get_db)):
    AuthService.reset_password(db, reset_data.token, reset_data.new_password)
    return ResponseModel(
        success=True,
        message="Password reset successful."
    )

@router.delete("/account", response_model=ResponseModel)
def delete_account(
    delete_data: DeleteAccountRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    from core.security.jwt import verify_password
    if not verify_password(delete_data.password, current_user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Current password must match"
        )
        
    AuthService.soft_delete_user(db, current_user)
    return ResponseModel(
        success=True,
        message="Account deleted successfully."
    )

@router.post("/request-verification", response_model=ResponseModel)
def request_verification(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    from datetime import timedelta
    from core.security.jwt import create_access_token
    from core.logging.logger import logger
    
    # Generate verification token valid for 24 hours
    token = create_access_token(
        data={"sub": current_user.id, "type": "email_verification"},
        expires_delta=timedelta(hours=24)
    )
    logger.info(f"Verification token generated for user {current_user.email}: {token}")
    return ResponseModel(
        success=True,
        message="Verification email requested.",
        data={"token": token}
    )

@router.post("/verify-email", response_model=ResponseModel)
def verify_email(
    data: VerifyEmailRequest,
    db: Session = Depends(get_db)
):
    from core.security.jwt import decode_access_token
    payload = decode_access_token(data.token)
    if not payload or payload.get("type") != "email_verification":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired verification token"
        )
    user_id = payload.get("sub")
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    user.is_verified = True
    db.commit()
    return ResponseModel(
        success=True,
        message="Email verified successfully."
    )

@router.post("/logout-all", response_model=ResponseModel)
def logout_all(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    from features.auth.models import UserSession
    # Deactivate all active sessions for current user
    sessions = db.query(UserSession).filter(
        UserSession.user_id == current_user.id,
        UserSession.is_active == True
    ).all()
    for session in sessions:
        session.is_active = False
    db.commit()
    return ResponseModel(
        success=True,
        message="Logged out from all devices successfully."
    )


# Nested Admin User Management Router
from app.dependencies import RoleChecker
from features.auth.schemas import (
    AdminUserResponse, PermissionResponse, RoleResponse,
    UserRoleUpdate, RolePermissionsUpdate, UserSessionResponse
)
from typing import List

admin_router = APIRouter(prefix="/admin", dependencies=[Depends(RoleChecker(["Administrator"]))])

@admin_router.get("/users", response_model=ResponseModel)
def list_users(db: Session = Depends(get_db)):
    users = AuthService.get_all_users(db)
    user_list = [
        AdminUserResponse(
            id=u.id,
            full_name=u.full_name,
            email=u.email,
            role=u.role.name,
            is_active=u.is_active,
            is_verified=u.is_verified,
            last_login=u.last_login,
            created_at=u.created_at
        )
        for u in users
    ]
    return ResponseModel(success=True, message="Users list retrieved successfully.", data=user_list)

@admin_router.put("/users/{user_id}/role", response_model=ResponseModel)
def update_user_role_route(user_id: str, role_data: UserRoleUpdate, db: Session = Depends(get_db)):
    AuthService.update_user_role(db, user_id, role_data.role_name)
    return ResponseModel(success=True, message=f"User role updated to {role_data.role_name} successfully.")

@admin_router.post("/users/{user_id}/suspend", response_model=ResponseModel)
def suspend_user_route(user_id: str, db: Session = Depends(get_db)):
    AuthService.suspend_user(db, user_id)
    return ResponseModel(success=True, message="User suspended successfully.")

@admin_router.post("/users/{user_id}/activate", response_model=ResponseModel)
def activate_user_route(user_id: str, db: Session = Depends(get_db)):
    AuthService.activate_user(db, user_id)
    return ResponseModel(success=True, message="User activated successfully.")

@admin_router.delete("/users/{user_id}", response_model=ResponseModel)
def delete_user_route(user_id: str, db: Session = Depends(get_db)):
    AuthService.delete_user_by_admin(db, user_id)
    return ResponseModel(success=True, message="User deleted successfully.")

@admin_router.get("/users/{user_id}/sessions", response_model=ResponseModel)
def list_user_sessions(user_id: str, db: Session = Depends(get_db)):
    sessions = AuthService.get_user_sessions(db, user_id)
    
    def mask_token(t: str) -> str:
        if len(t) <= 12:
            return "****"
        return f"{t[:6]}...{t[-6:]}"
        
    session_list = [
        UserSessionResponse(
            id=s.id,
            is_active=s.is_active,
            expires_at=s.expires_at,
            created_at=s.created_at,
            access_token_masked=mask_token(s.access_token),
            refresh_token_masked=mask_token(s.refresh_token)
        )
        for s in sessions
    ]
    return ResponseModel(success=True, message="User sessions retrieved successfully.", data=session_list)

@admin_router.post("/users/{user_id}/sessions/revoke-all", response_model=ResponseModel)
def revoke_all_sessions_route(user_id: str, db: Session = Depends(get_db)):
    AuthService.revoke_all_user_sessions(db, user_id)
    return ResponseModel(success=True, message="All active sessions for this user have been revoked.")

@admin_router.post("/sessions/{session_id}/revoke", response_model=ResponseModel)
def revoke_single_session_route(session_id: str, db: Session = Depends(get_db)):
    AuthService.revoke_session(db, session_id)
    return ResponseModel(success=True, message="Session revoked successfully.")

@admin_router.get("/roles", response_model=ResponseModel)
def list_roles(db: Session = Depends(get_db)):
    roles = AuthService.get_all_roles(db)
    role_list = [
        RoleResponse(
            id=r.id,
            name=r.name,
            description=r.description,
            created_at=r.created_at,
            permissions=[
                PermissionResponse(id=p.id, name=p.name, description=p.description, created_at=p.created_at)
                for p in r.permissions
            ]
        )
        for r in roles
    ]
    return ResponseModel(success=True, message="Roles list retrieved successfully.", data=role_list)

@admin_router.put("/roles/{role_id}/permissions", response_model=ResponseModel)
def update_role_permissions_route(role_id: str, perm_data: RolePermissionsUpdate, db: Session = Depends(get_db)):
    AuthService.update_role_permissions(db, role_id, perm_data.permission_names)
    return ResponseModel(success=True, message="Role permissions updated successfully.")

@admin_router.get("/permissions", response_model=ResponseModel)
def list_permissions(db: Session = Depends(get_db)):
    perms = AuthService.get_all_permissions(db)
    perm_list = [
        PermissionResponse(id=p.id, name=p.name, description=p.description, created_at=p.created_at)
        for p in perms
    ]
    return ResponseModel(success=True, message="Permissions list retrieved successfully.", data=perm_list)

router.include_router(admin_router)

