"""add_furniture_catalog_tables

Revision ID: 55f726c8f485
Revises: b6a534ee668b
Create Date: 2026-08-08 18:21:21.154391

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '55f726c8f485'
down_revision: Union[str, Sequence[str], None] = 'b6a534ee668b'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # 1. Create furniture_categories table
    op.create_table('furniture_categories',
    sa.Column('id', sa.String(length=36), nullable=False),
    sa.Column('name', sa.String(length=50), nullable=False),
    sa.Column('description', sa.Text(), nullable=True),
    sa.Column('created_at', sa.DateTime(), nullable=False),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('name')
    )

    # 2. Add columns and foreign keys to furniture_assets
    with op.batch_alter_table('furniture_assets') as batch_op:
        batch_op.add_column(sa.Column('category_id', sa.String(length=36), nullable=True))
        batch_op.add_column(sa.Column('model_path', sa.String(length=255), nullable=True))
        batch_op.add_column(sa.Column('thumbnail_path', sa.String(length=255), nullable=True))
        batch_op.create_foreign_key('fk_furniture_assets_category_id', 'furniture_categories', ['category_id'], ['id'], ondelete='SET NULL')

    # 3. Create furniture_materials table
    op.create_table('furniture_materials',
    sa.Column('id', sa.String(length=36), nullable=False),
    sa.Column('furniture_id', sa.String(length=36), nullable=False),
    sa.Column('material_id', sa.String(length=36), nullable=False),
    sa.Column('is_default', sa.Boolean(), nullable=False, server_default='0'),
    sa.Column('created_at', sa.DateTime(), nullable=False),
    sa.ForeignKeyConstraint(['furniture_id'], ['furniture_assets.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['material_id'], ['materials.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id')
    )

    # 4. Create furniture_favorites table
    op.create_table('furniture_favorites',
    sa.Column('id', sa.String(length=36), nullable=False),
    sa.Column('user_id', sa.String(length=36), nullable=False),
    sa.Column('furniture_id', sa.String(length=36), nullable=False),
    sa.Column('created_at', sa.DateTime(), nullable=False),
    sa.ForeignKeyConstraint(['furniture_id'], ['furniture_assets.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('user_id', 'furniture_id', name='uq_user_furniture_favorite')
    )

    # 5. Create furniture_recent table
    op.create_table('furniture_recent',
    sa.Column('id', sa.String(length=36), nullable=False),
    sa.Column('user_id', sa.String(length=36), nullable=False),
    sa.Column('furniture_id', sa.String(length=36), nullable=False),
    sa.Column('last_used_at', sa.DateTime(), nullable=False),
    sa.ForeignKeyConstraint(['furniture_id'], ['furniture_assets.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('user_id', 'furniture_id', name='uq_user_furniture_recent')
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_table('furniture_recent')
    op.drop_table('furniture_favorites')
    op.drop_table('furniture_materials')
    with op.batch_alter_table('furniture_assets') as batch_op:
        batch_op.drop_constraint('fk_furniture_assets_category_id', type_='foreignkey')
        batch_op.drop_column('thumbnail_path')
        batch_op.drop_column('model_path')
        batch_op.drop_column('category_id')
    op.drop_table('furniture_categories')

