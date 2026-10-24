"""Add officer, visitor, and incident response fields.

Revision ID: 3ae94eab5e7e
Revises: 071d1b7955a5
"""

from alembic import op
import sqlalchemy as sa


# Revision identifiers used by Alembic.
revision = "3ae94eab5e7e"
down_revision = "071d1b7955a5"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Nullable columns preserve all existing account and response records.
    op.add_column(
        "officer_accounts",
        sa.Column("location", sa.String(length=200), nullable=True),
    )

    op.add_column(
        "visitors",
        sa.Column("last_login_at", sa.DateTime(), nullable=True),
    )

    op.add_column(
        "incident_responses",
        sa.Column("condition_status", sa.String(length=30), nullable=True),
    )

    op.add_column(
        "incident_responses",
        sa.Column("evacuation_status", sa.String(length=30), nullable=True),
    )

    op.add_column(
        "incident_responses",
        sa.Column("responded_at", sa.DateTime(), nullable=True),
    )


def downgrade() -> None:
    # Remove only the five columns introduced by this migration.
    op.drop_column("incident_responses", "responded_at")
    op.drop_column("incident_responses", "evacuation_status")
    op.drop_column("incident_responses", "condition_status")
    op.drop_column("visitors", "last_login_at")
    op.drop_column("officer_accounts", "location")
