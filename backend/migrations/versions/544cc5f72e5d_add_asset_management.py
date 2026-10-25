"""add_asset_management

Revision ID: 544cc5f72e5d
Revises: 55f726c8f485
Create Date: 2026-08-09 21:53:07.392801

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '544cc5f72e5d'
down_revision: Union[str, Sequence[str], None] = '55f726c8f485'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table('assets',
    sa.Column('id', sa.String(length=36), nullable=False),
    sa.Column('name', sa.String(length=100), nullable=False),
    sa.Column('type', sa.String(length=50), nullable=False),
    sa.Column('file_type', sa.String(length=10), nullable=False),
    sa.Column('model_path', sa.String(length=255), nullable=True),
    sa.Column('thumbnail_path', sa.String(length=255), nullable=True),
    sa.Column('preview_path', sa.String(length=255), nullable=True),
    sa.Column('asset_metadata', sa.Text(), nullable=True),
    sa.Column('created_at', sa.DateTime(), nullable=False),
    sa.PrimaryKeyConstraint('id')
    )
    
    with op.batch_alter_table('furniture_assets') as batch_op:
        batch_op.add_column(sa.Column('subcategory', sa.String(length=50), nullable=True))
        batch_op.add_column(sa.Column('model_asset_id', sa.String(length=36), nullable=True))
        batch_op.add_column(sa.Column('thumbnail_asset_id', sa.String(length=36), nullable=True))
        batch_op.add_column(sa.Column('preview_asset_id', sa.String(length=36), nullable=True))
        batch_op.add_column(sa.Column('preview_path', sa.String(length=255), nullable=True))
        
    with op.batch_alter_table('furniture_assets') as batch_op:
        batch_op.create_foreign_key('fk_fa_model_asset', 'assets', ['model_asset_id'], ['id'], ondelete='SET NULL')
        batch_op.create_foreign_key('fk_fa_thumbnail_asset', 'assets', ['thumbnail_asset_id'], ['id'], ondelete='SET NULL')
        batch_op.create_foreign_key('fk_fa_preview_asset', 'assets', ['preview_asset_id'], ['id'], ondelete='SET NULL')
        
    with op.batch_alter_table('furniture_categories') as batch_op:
        batch_op.add_column(sa.Column('parent_id', sa.String(length=36), nullable=True))
        batch_op.create_foreign_key('fk_fc_parent', 'furniture_categories', ['parent_id'], ['id'], ondelete='CASCADE')


def downgrade() -> None:
    """Downgrade schema."""
    with op.batch_alter_table('furniture_categories') as batch_op:
        batch_op.drop_constraint('fk_fc_parent', type_='foreignkey')
        batch_op.drop_column('parent_id')
        
    with op.batch_alter_table('furniture_assets') as batch_op:
        batch_op.drop_constraint('fk_fa_model_asset', type_='foreignkey')
        batch_op.drop_constraint('fk_fa_thumbnail_asset', type_='foreignkey')
        batch_op.drop_constraint('fk_fa_preview_asset', type_='foreignkey')
        batch_op.drop_column('preview_path')
        batch_op.drop_column('preview_asset_id')
        batch_op.drop_column('thumbnail_asset_id')
        batch_op.drop_column('model_asset_id')
        batch_op.drop_column('subcategory')
        
    op.drop_table('assets')
