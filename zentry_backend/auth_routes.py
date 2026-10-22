
import hashlib
import hmac
import os
import secrets
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from database import SessionLocal
from email_service import send_email
from models import EmailOTP, OfficerAccount
from security import (
    create_access_token,
    decode_access_token,
    hash_password,
    verify_password,
)

from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import InvalidTokenError
from models import EmailOTP, Employee, OfficerAccount
from models import EmailOTP, Employee, OfficerAccount, Visitor
from datetime import datetime, timedelta
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer


router = APIRouter(prefix="/auth", tags=["Authentication"])
bearer_scheme = HTTPBearer()

OTP_PEPPER = os.getenv("OTP_PEPPER", "")
ADMIN_REGISTRATION_CODE = os.getenv("ADMIN_REGISTRATION_CODE", "")


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def normalize_email(email: str) -> str:
    return email.strip().lower()


def hash_otp(email: str, purpose: str, code: str) -> str:
    if not OTP_PEPPER:
        raise RuntimeError("OTP_PEPPER is missing from .env")

    value = f"{email}:{purpose}:{code}:{OTP_PEPPER}"
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


class OfficerRegisterRequest(BaseModel):
    full_name: str = Field(min_length=2, max_length=120)
    email: str = Field(min_length=5, max_length=255)
    password: str = Field(min_length=12, max_length=128)
    role: str = "officer"
    admin_registration_code: str | None = None


class VerifyEmailRequest(BaseModel):
    email: str = Field(min_length=5, max_length=255)
    otp: str = Field(pattern=r"^\d{6}$")


class OfficerLoginRequest(BaseModel):
    email: str = Field(min_length=5, max_length=255)
    password: str = Field(min_length=1, max_length=128)


@router.post("/officer/register", status_code=201)
def register_officer(
    data: OfficerRegisterRequest,
    db: Session = Depends(get_db),
):
    email = normalize_email(data.email)
    full_name = data.full_name.strip()
    requested_role = data.role.strip().lower()

    if not full_name:
        raise HTTPException(400, "Full name is required.")

    if requested_role not in {"officer", "admin"}:
        raise HTTPException(400, "Role must be officer or admin.")

    if requested_role == "admin":
        if not ADMIN_REGISTRATION_CODE:
            raise HTTPException(
                403,
                "Admin self-registration is disabled. Ask the system owner.",
            )

        supplied_code = data.admin_registration_code or ""
        if not hmac.compare_digest(
            supplied_code,
            ADMIN_REGISTRATION_CODE,
        ):
            raise HTTPException(403, "Invalid admin registration code.")

    existing = (
        db.query(OfficerAccount)
        .filter(OfficerAccount.email == email)
        .first()
    )
    if existing:
        raise HTTPException(
            409,
            "An account already exists for this email address.",
        )

    code = f"{secrets.randbelow(1_000_000):06d}"
    now = datetime.utcnow()

    account = OfficerAccount(
        full_name=full_name,
        email=email,
        password_hash=hash_password(data.password),
        role=requested_role,
        is_active=True,
        email_verified_at=None,
    )

    otp_record = EmailOTP(
        email=email,
        purpose="OFFICER_REGISTER",
        code_hash=hash_otp(email, "OFFICER_REGISTER", code),
        expires_at=now + timedelta(minutes=10),
        consumed_at=None,
        attempts=0,
    )

    try:
        db.add(account)
        db.add(otp_record)
        db.flush()

        send_email(
            recipient=email,
            subject="Verify your Zentry account",
            body=(
                f"Hello {full_name},\n\n"
                f"Your Zentry email verification code is: {code}\n\n"
                "This code expires in 10 minutes and can be used once.\n"
                "If you did not request this account, ignore this email."
            ),
        )

        db.commit()
    except HTTPException:
        db.rollback()
        raise
    except Exception:
        db.rollback()
        raise HTTPException(
            status_code=503,
            detail=(
                "Registration could not be completed. "
                "Check the server email configuration and try again."
            ),
        )

    return {
        "message": "Registration created. Check your email for the OTP.",
        "email": email,
        "role": requested_role,
        "verification_required": True,
    }


@router.post("/verify-email")
def verify_officer_email(
    data: VerifyEmailRequest,
    db: Session = Depends(get_db),
):
    email = normalize_email(data.email)
    now = datetime.utcnow()

    account = (
        db.query(OfficerAccount)
        .filter(OfficerAccount.email == email)
        .first()
    )

    if account is None:
        raise HTTPException(404, "Registration not found.")

    if account.email_verified_at is not None:
        return {"message": "Email is already verified."}

    otp_record = (
        db.query(EmailOTP)
        .filter(
            EmailOTP.email == email,
            EmailOTP.purpose == "OFFICER_REGISTER",
            EmailOTP.consumed_at.is_(None),
        )
        .order_by(EmailOTP.id.desc())
        .first()
    )

    if otp_record is None:
        raise HTTPException(
            400,
            "No unused verification code found. Register again or request a new code.",
        )

    if otp_record.expires_at <= now:
        raise HTTPException(
            400,
            "Verification code expired. Request a new code.",
        )

    if otp_record.attempts >= 5:
        raise HTTPException(
            429,
            "Too many incorrect attempts. Request a new code.",
        )

    expected_hash = hash_otp(email, "OFFICER_REGISTER", data.otp)

    if not hmac.compare_digest(otp_record.code_hash, expected_hash):
        otp_record.attempts += 1
        db.commit()
        raise HTTPException(400, "Incorrect verification code.")

    otp_record.consumed_at = now
    account.email_verified_at = now
    db.commit()

    return {
        "message": "Email verified successfully.",
        "email": email,
        "role": account.role,
    }


@router.post("/officer/login")
def login_officer(
    data: OfficerLoginRequest,
    db: Session = Depends(get_db),
):
    email = normalize_email(data.email)

    account = (
        db.query(OfficerAccount)
        .filter(OfficerAccount.email == email)
        .first()
    )

    if account is None or not verify_password(
        data.password,
        account.password_hash,
    ):
        raise HTTPException(401, "Invalid email or password.")

    if not account.is_active:
        raise HTTPException(403, "This account is inactive.")

    if account.email_verified_at is None:
        raise HTTPException(
            403,
            "Verify your email before logging in.",
        )

    token = create_access_token(
        subject=str(account.id),
        account_type=account.role,
    )

    return {
        "access_token": token,
        "token_type": "bearer",
        "account": {
            "id": account.id,
            "full_name": account.full_name,
            "email": account.email,
            "role": account.role,
        },
    }


# --------------------------------------------------
# AUTHENTICATED ACCOUNT HELPERS
# --------------------------------------------------

def get_current_officer(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> OfficerAccount:
    token = credentials.credentials

    try:
        payload = decode_access_token(token)
        account_type = payload.get("account_type")
        account_id = int(payload["sub"])
    except (InvalidTokenError, KeyError, TypeError, ValueError):
        raise HTTPException(401, "Invalid or expired access token.")

    if account_type not in {"officer", "admin"}:
        raise HTTPException(403, "Officer access is required.")

    officer = db.get(OfficerAccount, account_id)

    if officer is None or not officer.is_active:
        raise HTTPException(401, "Officer account is inactive or unavailable.")

    if officer.email_verified_at is None:
        raise HTTPException(403, "Verify the officer email first.")

    if officer.role != account_type:
        raise HTTPException(401, "Token permissions are no longer valid.")

    return officer


def get_current_employee(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> Employee:
    try:
        payload = decode_access_token(credentials.credentials)
        account_type = payload.get("account_type")
        employee_id = int(payload["sub"])
    except (InvalidTokenError, KeyError, TypeError, ValueError):
        raise HTTPException(401, "Invalid or expired access token.")

    if account_type != "employee":
        raise HTTPException(403, "Employee access is required.")

    employee = db.get(Employee, employee_id)

    if employee is None or not employee.is_active:
        raise HTTPException(401, "Employee account is inactive or unavailable.")

    return employee

def get_current_visitor(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> Visitor:
    token = credentials.credentials

    try:
        payload = decode_access_token(token)
    except InvalidTokenError:
        raise HTTPException(
            status_code=401,
            detail="Invalid or expired access token.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if payload.get("account_type") != "visitor":
        raise HTTPException(
            status_code=403,
            detail="Visitor access is required.",
        )

    visitor_id = payload.get("sub")

    if not visitor_id or not str(visitor_id).isdigit():
        raise HTTPException(
            status_code=401,
            detail="Invalid visitor token.",
        )

    visitor = db.get(Visitor, int(visitor_id))

    if visitor is None or not visitor.is_active:
        raise HTTPException(
            status_code=403,
            detail="Visitor account is inactive.",
        )

    now = datetime.utcnow()

    if visitor.expires_at is None or visitor.expires_at <= now:
        visitor.is_active = 0
        db.commit()

        raise HTTPException(
            status_code=403,
            detail="Visitor access has expired. Please register again.",
        )

    if visitor.email_verified_at is None:
        raise HTTPException(
            status_code=403,
            detail="Visitor email verification is required.",
        )

    return visitor

# --------------------------------------------------
# EMPLOYEE ACCOUNT CREATION
# --------------------------------------------------

class EmployeeCreateRequest(BaseModel):
    employee_code: str = Field(min_length=1, max_length=50)
    full_name: str = Field(min_length=2, max_length=120)
    email: str = Field(min_length=5, max_length=255)


@router.post("/officers/employees", status_code=201)
def create_employee(
    data: EmployeeCreateRequest,
    officer: OfficerAccount = Depends(get_current_officer),
    db: Session = Depends(get_db),
):
    employee_code = data.employee_code.strip()
    full_name = data.full_name.strip()
    email = normalize_email(data.email)

    if not employee_code or not full_name:
        raise HTTPException(400, "Employee code and full name are required.")

    existing_code = (
        db.query(Employee)
        .filter(Employee.employee_code == employee_code)
        .first()
    )
    if existing_code:
        raise HTTPException(409, "This employee code already exists.")

    existing_email = (
        db.query(Employee)
        .filter(Employee.email == email)
        .first()
    )
    if existing_email:
        raise HTTPException(409, "An employee already uses this email.")

    temporary_password = secrets.token_urlsafe(12)

    employee = Employee(
        employee_code=employee_code,
        full_name=full_name,
        email=email,
        is_active=True,
        password_hash=hash_password(temporary_password),
        password_reset_required=True,
    )

    try:
        db.add(employee)
        db.flush()

        send_email(
            recipient=email,
            subject="Your Zentry employee account",
            body=(
                f"Hello {full_name},\n\n"
                "An employee account has been created for you in Zentry.\n\n"
                f"Employee ID: {employee_code}\n"
                f"Login email: {email}\n"
                f"Temporary password: {temporary_password}\n\n"
                "Sign in to the Zentry app and change your password "
                "before using your account.\n\n"
                "For your security, do not share this password."
            ),
        )

        db.commit()
        db.refresh(employee)

    except Exception as exc:
        db.rollback()
        if isinstance(exc, HTTPException):
            raise
        raise HTTPException(
            503,
            "Employee creation or email delivery failed. Check server logs.",
        )

    return {
        "message": "Employee account created and temporary password emailed.",
        "employee": {
            "id": employee.id,
            "employee_code": employee.employee_code,
            "full_name": employee.full_name,
            "email": employee.email,
            "password_reset_required": employee.password_reset_required,
        },
        "created_by": officer.email,
    }


# --------------------------------------------------
# EMPLOYEE LOGIN
# --------------------------------------------------

class EmployeeLoginRequest(BaseModel):
    email: str = Field(min_length=5, max_length=255)
    password: str = Field(min_length=1, max_length=128)


@router.post("/employee/login")
def login_employee(
    data: EmployeeLoginRequest,
    db: Session = Depends(get_db),
):
    email = normalize_email(data.email)

    employee = (
        db.query(Employee)
        .filter(Employee.email == email)
        .first()
    )

    if (
        employee is None
        or not employee.password_hash
        or not verify_password(data.password, employee.password_hash)
    ):
        raise HTTPException(401, "Invalid email or password.")

    if not employee.is_active:
        raise HTTPException(403, "This employee account is inactive.")

    token = create_access_token(
        subject=str(employee.id),
        account_type="employee",
    )

    return {
        "access_token": token,
        "token_type": "bearer",
        "must_change_password": bool(employee.password_reset_required),
        "account": {
            "id": employee.id,
            "employee_code": employee.employee_code,
            "full_name": employee.full_name,
            "email": employee.email,
            "account_type": "employee",
        },
    }


# --------------------------------------------------
# EMPLOYEE PASSWORD CHANGE
# --------------------------------------------------

class EmployeeChangePasswordRequest(BaseModel):
    current_password: str | None = Field(default=None, max_length=128)
    new_password: str = Field(min_length=12, max_length=128)


@router.post("/employee/change-password")
def change_employee_password(
    data: EmployeeChangePasswordRequest,
    employee: Employee = Depends(get_current_employee),
    db: Session = Depends(get_db),
):
    if data.current_password is None:
        if not employee.password_reset_required:
            raise HTTPException(
                400,
                "Current password is required to change your password.",
            )
    elif not employee.password_hash or not verify_password(
        data.current_password,
        employee.password_hash,
    ):
        raise HTTPException(400, "Current password is incorrect.")

    if data.current_password == data.new_password:
        raise HTTPException(
            400,
            "New password must be different from the current password.",
        )

    employee.password_hash = hash_password(data.new_password)
    employee.password_reset_required = False

    db.commit()

    return {
        "message": "Password changed successfully.",
        "password_reset_required": False,
    }


# --------------------------------------------------
# VISITOR REGISTRATION AND OTP AUTHENTICATION
# --------------------------------------------------

class VisitorRegisterRequest(BaseModel):
    full_name: str = Field(min_length=2, max_length=120)
    email: str = Field(min_length=5, max_length=255)


class VisitorVerifyRequest(BaseModel):
    vrf_id: str = Field(min_length=6, max_length=50)
    email: str = Field(min_length=5, max_length=255)
    otp: str = Field(pattern=r"^\d{6}$")


@router.post("/visitor/register", status_code=201)
def register_visitor(
    data: VisitorRegisterRequest,
    db: Session = Depends(get_db),
):
    email = normalize_email(data.email)
    full_name = data.full_name.strip()

    if not full_name:
        raise HTTPException(400, "Full name is required.")

    # Prevent duplicate pending registrations for the same email.
    pending = (
        db.query(Visitor)
        .filter(
            Visitor.email == email,
            Visitor.is_active == 0,
            Visitor.email_verified_at.is_(None),
        )
        .first()
    )
    if pending:
        raise HTTPException(
            409,
            "A visitor registration is already pending for this email. "
            "Please contact the safety officer.",
        )

    # Generate the next sequential VBVID ID.
    existing_ids = db.query(Visitor.vrf_id).all()
    highest_number = 0

    for (existing_id,) in existing_ids:
        if existing_id.startswith("VBVID"):
            suffix = existing_id[5:]
            if suffix.isdigit():
                highest_number = max(highest_number, int(suffix))

    vrf_id = f"VBVID{highest_number + 1}"

    # Ensure the generated ID is not already present.
    while db.query(Visitor.id).filter(Visitor.vrf_id == vrf_id).first():
        highest_number += 1
        vrf_id = f"VBVID{highest_number + 1}"

    code = f"{secrets.randbelow(1_000_000):06d}"
    now = datetime.utcnow()

    visitor = Visitor(
        vrf_id=vrf_id,
        full_name=full_name,
        email=email,
        is_active=0,
        email_verified_at=None,
        expires_at=None,
    )

    otp_record = EmailOTP(
        email=email,
        purpose="VISITOR_REGISTER",
        code_hash=hash_otp(email, "VISITOR_REGISTER", code),
        expires_at=now + timedelta(minutes=10),
        consumed_at=None,
        attempts=0,
    )

    try:
        db.add(visitor)
        db.add(otp_record)
        db.flush()

        send_email(
            recipient=email,
            subject="Your Zentry visitor verification code",
            body=(
                f"Hello {full_name},\n\n"
                f"Your visitor VRF ID is: {vrf_id}\n"
                f"Your email verification code is: {code}\n\n"
                "The verification code expires in 10 minutes.\n"
                "After verification, your visitor access lasts up to 9 hours.\n"
                "If you did not request this registration, ignore this email."
            ),
        )

        db.commit()

    except Exception:
        db.rollback()
        raise HTTPException(
            503,
            "Visitor registration or email delivery failed. "
            "Check server email configuration and try again.",
        )

    return {
        "message": "Visitor registration created. Check your email for the OTP.",
        "vrf_id": vrf_id,
        "email": email,
        "verification_required": True,
    }


@router.post("/visitor/verify-email")
def verify_visitor_email(
    data: VisitorVerifyRequest,
    db: Session = Depends(get_db),
):
    email = normalize_email(data.email)
    vrf_id = data.vrf_id.strip().upper()
    now = datetime.utcnow()

    visitor = (
        db.query(Visitor)
        .filter(
            Visitor.vrf_id == vrf_id,
            Visitor.email == email,
        )
        .first()
    )

    if visitor is None:
        raise HTTPException(404, "Visitor registration not found.")

    if visitor.email_verified_at is not None and visitor.is_active:
        raise HTTPException(
            409,
            "This visitor registration has already been verified.",
        )

    otp_record = (
        db.query(EmailOTP)
        .filter(
            EmailOTP.email == email,
            EmailOTP.purpose == "VISITOR_REGISTER",
            EmailOTP.consumed_at.is_(None),
        )
        .order_by(EmailOTP.id.desc())
        .first()
    )

    if otp_record is None:
        raise HTTPException(400, "No unused visitor verification code found.")

    if otp_record.expires_at <= now:
        raise HTTPException(400, "Verification code expired.")

    if otp_record.attempts >= 5:
        raise HTTPException(
            429,
            "Too many incorrect attempts. Contact the safety officer.",
        )

    expected_hash = hash_otp(email, "VISITOR_REGISTER", data.otp)

    if not hmac.compare_digest(otp_record.code_hash, expected_hash):
        otp_record.attempts += 1
        db.commit()
        raise HTTPException(400, "Incorrect verification code.")

    visitor.email_verified_at = now
    visitor.is_active = 1
    visitor.expires_at = now + timedelta(hours=9)
    otp_record.consumed_at = now

    try:
        db.commit()
        db.refresh(visitor)
    except Exception:
        db.rollback()
        raise HTTPException(500, "Unable to verify visitor registration.")

    token = create_access_token(
        subject=str(visitor.id),
        account_type="visitor",
        expires_minutes=540,
    )

    return {
        "message": "Visitor email verified successfully.",
        "access_token": token,
        "token_type": "bearer",
        "account": {
            "id": visitor.id,
            "vrf_id": visitor.vrf_id,
            "full_name": visitor.full_name,
            "email": visitor.email,
            "account_type": "visitor",
            "expires_at": visitor.expires_at.isoformat(),
        },
    }
