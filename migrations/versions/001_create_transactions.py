"""Criação da tabela transactions.

Revision ID: 001
Create Date: 2026-04-24
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Cria a tabela transactions com enums e índices."""
    # Criar enums
    card_type_enum = sa.Enum("credit", "debit", name="card_type_enum")
    transaction_status_enum = sa.Enum("approved", "declined", "pending", name="transaction_status_enum")

    card_type_enum.create(op.get_bind(), checkfirst=True)
    transaction_status_enum.create(op.get_bind(), checkfirst=True)

    op.create_table(
        "transactions",
        sa.Column("id", sa.Uuid(), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("amount", sa.Numeric(precision=10, scale=2), nullable=False),
        sa.Column("card_type", card_type_enum, nullable=False),
        sa.Column("card_number_hash", sa.String(64), nullable=False),
        sa.Column("status", transaction_status_enum, nullable=False, server_default="pending"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
    )

    # Índices para queries comuns
    op.create_index("ix_transactions_status", "transactions", ["status"])
    op.create_index("ix_transactions_card_type", "transactions", ["card_type"])
    op.create_index("ix_transactions_created_at", "transactions", ["created_at"])


def downgrade() -> None:
    """Remove a tabela transactions e os enums."""
    op.drop_index("ix_transactions_created_at")
    op.drop_index("ix_transactions_card_type")
    op.drop_index("ix_transactions_status")
    op.drop_table("transactions")

    sa.Enum(name="transaction_status_enum").drop(op.get_bind(), checkfirst=True)
    sa.Enum(name="card_type_enum").drop(op.get_bind(), checkfirst=True)
