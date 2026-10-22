
from datetime import datetime

from sqlalchemy import (
    String,
    Integer,
    DateTime,
    ForeignKey,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from database import Base


class Employee(Base):
    __tablename__ = "employees"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    employee_code: Mapped[str] = mapped_column(
        String(50), unique=True, nullable=False
    )
    full_name: Mapped[str] = mapped_column(String(120), nullable=False)
    email: Mapped[str] = mapped_column(
        String(255), unique=True, nullable=False
    )
    is_active: Mapped[int] = mapped_column(Integer, default=1, nullable=False)

    # Existing employees can receive credentials without deleting their records.
    password_hash: Mapped[str | None] = mapped_column(
        String(255), nullable=True
    )
    password_reset_required: Mapped[int] = mapped_column(
        Integer, default=1, server_default="1", nullable=False
    )

    responses: Mapped[list["IncidentResponse"]] = relationship(
        back_populates="employee"
    )


class OfficerAccount(Base):
    __tablename__ = "officer_accounts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    full_name: Mapped[str] = mapped_column(String(120), nullable=False)
    email: Mapped[str] = mapped_column(
        String(255), unique=True, nullable=False
    )
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    role: Mapped[str] = mapped_column(
        String(20), default="OFFICER", nullable=False
    )
    is_active: Mapped[int] = mapped_column(
        Integer, default=1, server_default="1", nullable=False
    )
    email_verified_at: Mapped[datetime | None] = mapped_column(
        DateTime, nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), nullable=False
    )


class Visitor(Base):
    __tablename__ = "visitors"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    vrf_id: Mapped[str] = mapped_column(
        String(50), unique=True, nullable=False
    )
    full_name: Mapped[str] = mapped_column(String(120), nullable=False)
    email: Mapped[str] = mapped_column(String(255), nullable=False)
    is_active: Mapped[int] = mapped_column(
        Integer, default=1, server_default="1", nullable=False
    )
    email_verified_at: Mapped[datetime | None] = mapped_column(
        DateTime, nullable=True
    )
    expires_at: Mapped[datetime | None] = mapped_column(
        DateTime, nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), nullable=False
    )

    responses: Mapped[list["IncidentResponse"]] = relationship(
        back_populates="visitor"
    )


class EmailOTP(Base):
    __tablename__ = "email_otps"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    email: Mapped[str] = mapped_column(String(255), nullable=False)
    purpose: Mapped[str] = mapped_column(String(30), nullable=False)
    code_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    consumed_at: Mapped[datetime | None] = mapped_column(
        DateTime, nullable=True
    )
    attempts: Mapped[int] = mapped_column(
        Integer, default=0, server_default="0", nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), nullable=False
    )


class Incident(Base):
    __tablename__ = "incidents"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    message: Mapped[str] = mapped_column(Text, nullable=False)
    location: Mapped[str] = mapped_column(String(200), nullable=False)
    status: Mapped[str] = mapped_column(String(30), default="ACTIVE")
    created_by: Mapped[str] = mapped_column(String(120), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), nullable=False
    )

    cleared_at: Mapped[datetime | None] = mapped_column(
        DateTime, nullable=True
    )

    responses: Mapped[list["IncidentResponse"]] = relationship(
        back_populates="incident",
        cascade="all, delete-orphan",
    )


class IncidentResponse(Base):
    __tablename__ = "incident_responses"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    incident_id: Mapped[int] = mapped_column(
        ForeignKey("incidents.id"), nullable=False
    )

    # A response belongs to either an employee or a visitor.
    # The migration must make the existing employee_id column nullable.
    employee_id: Mapped[int | None] = mapped_column(
        ForeignKey("employees.id"), nullable=True
    )
    visitor_id: Mapped[int | None] = mapped_column(
        ForeignKey("visitors.id"), nullable=True
    )

    response_status: Mapped[str] = mapped_column(
        String(30), default="NO_RESPONSE", nullable=False
    )
    message: Mapped[str | None] = mapped_column(Text, nullable=True)
    location_details: Mapped[str | None] = mapped_column(
        String(200), nullable=True
    )
    assigned_to_officer_id: Mapped[int | None] = mapped_column(
        ForeignKey("officer_accounts.id"), nullable=True
    )
    dispatched_at: Mapped[datetime | None] = mapped_column(
        DateTime, nullable=True
    )
    located_at: Mapped[datetime | None] = mapped_column(
        DateTime, nullable=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    incident: Mapped["Incident"] = relationship(back_populates="responses")
    employee: Mapped["Employee | None"] = relationship(
        back_populates="responses"
    )
    visitor: Mapped["Visitor | None"] = relationship(
        back_populates="responses"
    )

    __table_args__ = (
        UniqueConstraint(
            "incident_id",
            "employee_id",
            name="uq_incident_employee",
        ),
        UniqueConstraint(
            "incident_id",
            "visitor_id",
            name="uq_incident_visitor",
        ),
    )


class IncidentAuditLog(Base):
    __tablename__ = "incident_audit_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    incident_id: Mapped[int] = mapped_column(
        ForeignKey("incidents.id"), nullable=False
    )
    actor_type: Mapped[str] = mapped_column(String(20), nullable=False)
    actor_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    action: Mapped[str] = mapped_column(String(80), nullable=False)
    details: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), nullable=False
    )
