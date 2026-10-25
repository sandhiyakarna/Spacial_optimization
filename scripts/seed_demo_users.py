import os
import sys

# Ensure backend directory is in sys.path
backend_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backend")
sys.path.insert(0, backend_dir)

from core.database.session import SessionLocal
from features.auth.models import User, Role, UserPreference
from core.security.jwt import hash_password
from features.auth.services import seed_roles_and_permissions

def seed_demo_users():
    db = SessionLocal()
    try:
        print("Seeding roles and permissions...")
        seed_roles_and_permissions(db)
        
        users_to_seed = [
            {
                "email": "admin@flowspace.com",
                "full_name": "System Administrator",
                "password": "AdminPassword123!",
                "role_name": "Administrator"
            },
            {
                "email": "designer@flowspace.com",
                "full_name": "Lead Interior Designer",
                "password": "DesignerPassword123!",
                "role_name": "Interior Designer"
            },
            {
                "email": "user@flowspace.com",
                "full_name": "Demo Customer",
                "password": "UserPassword123!",
                "role_name": "Customer"
            }
        ]
        
        for u_data in users_to_seed:
            existing = db.query(User).filter(User.email == u_data["email"]).first()
            role = db.query(Role).filter(Role.name == u_data["role_name"]).first()
            if not role:
                print(f"Role {u_data['role_name']} not found, skipping user {u_data['email']}")
                continue
                
            if existing:
                existing.full_name = u_data["full_name"]
                existing.password_hash = hash_password(u_data["password"])
                existing.role_id = role.id
                existing.is_active = True
                print(f"Updated user: {u_data['email']}")
            else:
                new_user = User(
                    full_name=u_data["full_name"],
                    email=u_data["email"],
                    password_hash=hash_password(u_data["password"]),
                    role_id=role.id,
                    is_active=True
                )
                db.add(new_user)
                db.commit()
                db.refresh(new_user)
                
                # Add default user preference
                db.add(UserPreference(user_id=new_user.id))
                db.commit()
                print(f"Created user: {u_data['email']}")
                
        db.commit()
        print("Demo users successfully seeded!")
    finally:
        db.close()

if __name__ == "__main__":
    seed_demo_users()
