"""client reports (crashes + feedback)

Revision ID: 0002
Revises: 0001
Create Date: 2026-11-14
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0002"
down_revision: str | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "client_reports",
        sa.Column("kind", sa.String(length=12), nullable=False),
        sa.Column("message", sa.Text(), nullable=False),
        sa.Column("details", sa.Text(), nullable=True),
        sa.Column("app_version", sa.String(length=32), nullable=True),
        sa.Column("fingerprint", sa.String(length=64), nullable=True),
        sa.Column("count", sa.Integer(), nullable=False),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("status", sa.String(length=12), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], name=op.f("fk_client_reports_user_id_users"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_client_reports")),
    )
    op.create_index(op.f("ix_client_reports_user_id"), "client_reports", ["user_id"], unique=False)
    op.create_index(
        "ix_client_reports_user_fingerprint", "client_reports", ["user_id", "fingerprint"], unique=False
    )


def downgrade() -> None:
    op.drop_index("ix_client_reports_user_fingerprint", table_name="client_reports")
    op.drop_index(op.f("ix_client_reports_user_id"), table_name="client_reports")
    op.drop_table("client_reports")
