"""friends, sharing and group habits

Revision ID: 0003
Revises: 0002
Create Date: 2026-11-14
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0003"
down_revision: str | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _id():
    return sa.Column("id", sa.Uuid(), nullable=False)


def _created():
    return sa.Column("created_at", sa.DateTime(timezone=True), nullable=False)


def _user(name: str, nullable: bool = False, ondelete: str = "CASCADE"):
    return sa.Column(name, sa.Uuid(), sa.ForeignKey("users.id", ondelete=ondelete), nullable=nullable)


def upgrade() -> None:
    op.add_column("users", sa.Column("friend_code", sa.String(length=12), nullable=True))
    op.create_index("uq_users_friend_code", "users", ["friend_code"], unique=True)
    op.add_column(
        "habits", sa.Column("visibility", sa.String(length=12), nullable=False, server_default="private")
    )

    op.create_table(
        "friendships",
        _id(),
        _created(),
        _user("user_id"),
        _user("friend_id"),
        sa.Column("status", sa.String(length=12), nullable=False),
        sa.Column("accepted_at", sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint("id", name="pk_friendships"),
        sa.UniqueConstraint("user_id", "friend_id", name="uq_friendships_pair"),
    )
    op.create_index("ix_friendships_user_id", "friendships", ["user_id"])
    op.create_index("ix_friendships_friend_id", "friendships", ["friend_id"])

    op.create_table(
        "friend_groups",
        _id(),
        _created(),
        sa.Column("name", sa.String(length=60), nullable=False),
        _user("owner_id", nullable=True, ondelete="SET NULL"),
        sa.Column("invite_code", sa.String(length=16), nullable=False),
        sa.PrimaryKeyConstraint("id", name="pk_friend_groups"),
        sa.UniqueConstraint("invite_code", name="uq_friend_groups_invite_code"),
    )
    op.create_table(
        "group_members",
        _created(),
        sa.Column("group_id", sa.Uuid(), sa.ForeignKey("friend_groups.id", ondelete="CASCADE"), nullable=False),
        _user("user_id"),
        sa.PrimaryKeyConstraint("group_id", "user_id", name="pk_group_members"),
    )
    op.create_index("ix_group_members_user_id", "group_members", ["user_id"])
    op.create_table(
        "group_habits",
        _id(),
        _created(),
        sa.Column("group_id", sa.Uuid(), sa.ForeignKey("friend_groups.id", ondelete="CASCADE"), nullable=False),
        sa.Column("title", sa.String(length=120), nullable=False),
        sa.Column("recurrence_rule", sa.String(length=255), nullable=False),
        sa.Column("target_per_period", sa.Integer(), nullable=False),
        _user("created_by", nullable=True, ondelete="SET NULL"),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint("id", name="pk_group_habits"),
    )
    op.create_index("ix_group_habits_group_id", "group_habits", ["group_id"])
    op.create_table(
        "group_checkins",
        _id(),
        _created(),
        sa.Column(
            "group_habit_id", sa.Uuid(), sa.ForeignKey("group_habits.id", ondelete="CASCADE"), nullable=False
        ),
        _user("user_id"),
        sa.Column("day", sa.Date(), nullable=False),
        sa.PrimaryKeyConstraint("id", name="pk_group_checkins"),
        sa.UniqueConstraint("group_habit_id", "user_id", "day", name="uq_group_checkins_once"),
    )
    op.create_index("ix_group_checkins_group_habit_id", "group_checkins", ["group_habit_id"])
    op.create_index("ix_group_checkins_user_id", "group_checkins", ["user_id"])
    op.create_table(
        "reactions",
        _id(),
        _created(),
        _user("user_id"),
        _user("to_user_id"),
        sa.Column("kind", sa.String(length=12), nullable=False),
        sa.Column("target", sa.String(length=80), nullable=False),
        sa.PrimaryKeyConstraint("id", name="pk_reactions"),
    )
    op.create_index("ix_reactions_user_id", "reactions", ["user_id"])
    op.create_index("ix_reactions_to_user_id", "reactions", ["to_user_id"])


def downgrade() -> None:
    for t in ("reactions", "group_checkins", "group_habits", "group_members", "friend_groups", "friendships"):
        op.drop_table(t)
    op.drop_column("habits", "visibility")
    op.drop_index("uq_users_friend_code", table_name="users")
    op.drop_column("users", "friend_code")
