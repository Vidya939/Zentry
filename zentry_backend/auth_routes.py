#auth_routes.py:
import hashlib
import hmac
import os
import secrets
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import InvalidTokenError
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from database import SessionLocal, ist_now, ist_iso
from email_service import send_email
from models import EmailOTP, Employee, OfficerAccount, Visitor
from security import (
    create_access_token,
    decode_access_token,
    hash_password,
    verify_password,
)


router = APIRouter(prefix="/auth", tags=["Authentication"])
bearer_scheme = HTTPBearer()

OTP_PEPPER = os.getenv("OTP_PEPPER", "")
ADMIN_REGISTRATION_CODE = os.getenv("ADMIN_REGISTRATION_CODE", "")

VISITOR_ACCESS_HOURS = 9
OTP_VALID_MINUTES = 10
OTP_MAX_ATTEMPTS = 5


# --------------------------------------------------
# DATABASE AND COMMON HELPERS
# --------------------------------------------------

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


def create_otp_record(
    db: Session,
    email: str,
    purpose: str,
    code: str,
    now: datetime,
):
    # Invalidate any previous unused OTP for this email and purpose.
    old_records = (
        db.query(EmailOTP)
        .filter(
            EmailOTP.email == email,
            EmailOTP.purpose == purpose,
            EmailOTP.consumed_at.is_(None),
        )
        .all()
    )

    for record in old_records:
        record.consumed_at = now

    record = EmailOTP(
        email=email,
        purpose=purpose,
        code_hash=hash_otp(email, purpose, code),
        expires_at=now + timedelta(minutes=OTP_VALID_MINUTES),
        consumed_at=None,
        attempts=0,
    )
    db.add(record)
    return record


def validate_otp(
    db: Session,
    email: str,
    purpose: str,
    supplied_code: str,
    now: datetime,
):
    record = (
        db.query(EmailOTP)
        .filter(
            EmailOTP.email == email,
            EmailOTP.purpose == purpose,
            EmailOTP.consumed_at.is_(None),
        )
        .order_by(EmailOTP.id.desc())
        .first()
    )

    if record is None:
        raise HTTPException(
            400,
            "No unused verification code found. Request a new code.",
        )

    if record.expires_at <= now:
        raise HTTPException(400, "Verification code expired. Request a new code.")

    if record.attempts >= OTP_MAX_ATTEMPTS:
        raise HTTPException(429, "Too many incorrect attempts. Request a new code.")

    expected = hash_otp(email, purpose, supplied_code)

    if not hmac.compare_digest(record.code_hash, expected):
        record.attempts += 1
        db.commit()
        raise HTTPException(400, "Incorrect verification code.")

    return record


def send_otp_email(email: str, name: str, code: str, subject: str):
    send_email(
        recipient=email,
        subject=subject,
        body=(
            f"Hello {name},\n\n"
            f"Your Zentry verification code is: {code}\n\n"
            f"This code expires in {OTP_VALID_MINUTES} minutes "
            "and can be used only once.\n\n"
            "If you did not request this code, you can ignore this email."
        ),
    )


def issue_visitor_token(visitor: Visitor):
    return create_access_token(
        subject=str(visitor.id),
        account_type="visitor",
        expires_minutes=VISITOR_ACCESS_HOURS * 60,
    )


def visitor_account_data(visitor: Visitor):
    return {
        "id": visitor.id,
        "vrf_id": visitor.vrf_id,
        "full_name": visitor.full_name,
        "email": visitor.email,
        "account_type": "visitor",
        "is_active": bool(visitor.is_active),
"expires_at": ist_iso(visitor.expires_at),
"last_login_at": ist_iso(visitor.last_login_at),
    }


def next_visitor_vrf_id(db: Session) -> str:
    existing_ids = db.query(Visitor.vrf_id).all()
    highest_number = 0

    for (existing_id,) in existing_ids:
        if existing_id and existing_id.startswith("VBVID"):
            suffix = existing_id[5:]
            if suffix.isdigit():
                highest_number = max(highest_number, int(suffix))

    candidate = highest_number + 1

    while (
        db.query(Visitor.id)
        .filter(Visitor.vrf_id == f"VBVID{candidate}")
        .first()
    ):
        candidate += 1

    return f"VBVID{candidate}"


# --------------------------------------------------
# REQUEST SCHEMAS
# --------------------------------------------------

class OfficerRegisterRequest(BaseModel):
    full_name: str = Field(min_length=2, max_length=120)
    email: str = Field(min_length=5, max_length=255)
    password: str = Field(min_length=12, max_length=128)
    role: str = "Safety Officer"
    admin_registration_code: str | None = None


class VerifyEmailRequest(BaseModel):
    email: str = Field(min_length=5, max_length=255)
    otp: str = Field(pattern=r"^\d{6}$")


class OfficerLoginRequest(BaseModel):
    email: str = Field(min_length=5, max_length=255)
    password: str = Field(min_length=1, max_length=128)


class EmployeeCreateRequest(BaseModel):
    employee_code: str = Field(min_length=1, max_length=50)
    full_name: str = Field(min_length=2, max_length=120)
    email: str = Field(min_length=5, max_length=255)


class EmployeeUpdateRequest(BaseModel):
    employee_code: str = Field(min_length=1, max_length=50)
    full_name: str = Field(min_length=2, max_length=120)
    email: str = Field(min_length=5, max_length=255)


class EmployeeStatusRequest(BaseModel):
    is_active: bool


class EmployeeLoginRequest(BaseModel):
    email: str = Field(min_length=5, max_length=255)
    password: str = Field(min_length=1, max_length=128)


class EmployeeChangePasswordRequest(BaseModel):
    current_password: str | None = Field(default=None, max_length=128)
    new_password: str = Field(min_length=12, max_length=128)


class PasswordResetRequest(BaseModel):
    email: str = Field(min_length=5, max_length=255)


class PasswordResetVerifyRequest(BaseModel):
    email: str = Field(min_length=5, max_length=255)
    otp: str = Field(pattern=r"^\d{6}$")
    new_password: str = Field(min_length=12, max_length=128)


class VisitorRegisterRequest(BaseModel):
    full_name: str = Field(min_length=2, max_length=120)
    email: str = Field(min_length=5, max_length=255)


class VisitorVerifyRequest(BaseModel):
    vrf_id: str = Field(min_length=6, max_length=50)
    email: str = Field(min_length=5, max_length=255)
    otp: str = Field(pattern=r"^\d{6}$")


class VisitorLoginRequest(BaseModel):
    email: str = Field(min_length=5, max_length=255)


class VisitorLoginVerifyRequest(BaseModel):
    email: str = Field(min_length=5, max_length=255)
    otp: str = Field(pattern=r"^\d{6}$")


class OfficerProfileUpdateRequest(BaseModel):
    full_name: str = Field(min_length=2, max_length=120)
    location: str | None = Field(default=None, max_length=255)


class VisitorStatusRequest(BaseModel):
    is_active: bool


# --------------------------------------------------
# OFFICER REGISTRATION AND LOGIN
# --------------------------------------------------

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
        if not hmac.compare_digest(supplied_code, ADMIN_REGISTRATION_CODE):
            raise HTTPException(403, "Invalid admin registration code.")

    existing = (
        db.query(OfficerAccount)
        .filter(OfficerAccount.email == email)
        .first()
    )
    if existing:
        raise HTTPException(409, "An account already exists for this email address.")

    now = ist_now()
    code = f"{secrets.randbelow(1_000_000):06d}"

    account = OfficerAccount(
        full_name=full_name,
        email=email,
        password_hash=hash_password(data.password),
        role=requested_role,
        is_active=True,
        email_verified_at=None,
    )

    try:
        db.add(account)
        create_otp_record(db, email, "OFFICER_REGISTER", code, now)
        db.flush()

        send_otp_email(
            email,
            full_name,
            code,
            "Verify your Zentry account",
        )
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(
            503,
            "Registration or email delivery failed. Check server email configuration.",
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
    now = ist_now()

    account = (
        db.query(OfficerAccount)
        .filter(OfficerAccount.email == email)
        .first()
    )
    if account is None:
        raise HTTPException(404, "Registration not found.")

    if account.email_verified_at is not None:
        return {"message": "Email is already verified."}

    otp_record = validate_otp(
        db, email, "OFFICER_REGISTER", data.otp, now
    )

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
        data.password, account.password_hash
    ):
        raise HTTPException(401, "Invalid email or password.")

    if not account.is_active:
        raise HTTPException(403, "This account is inactive.")

    if account.email_verified_at is None:
        raise HTTPException(403, "Verify your email before logging in.")

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
            "location": account.location,
        },
    }


# --------------------------------------------------
# AUTHENTICATED ACCOUNT HELPERS
# --------------------------------------------------

def get_current_officer(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> OfficerAccount:
    try:
        payload = decode_access_token(credentials.credentials)
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
    except (InvalidTokenError, KeyError, TypeError, ValueError) as exc:
        print(
            f"JWT validation failed in get_current_employee: "
            f"{type(exc).__name__}"
        )
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
    try:
        payload = decode_access_token(credentials.credentials)
        if payload.get("account_type") != "visitor":
            raise HTTPException(403, "Visitor access is required.")
        visitor_id = int(payload["sub"])
    except HTTPException:
        raise
    except (InvalidTokenError, KeyError, TypeError, ValueError) as exc:
        print(
            f"JWT validation failed in get_current_visitor: "
            f"{type(exc).__name__}"
        )
        raise HTTPException(401, "Invalid or expired access token.")

    visitor = db.get(Visitor, visitor_id)

    if visitor is None:
        raise HTTPException(401, "Visitor account is unavailable.")

    now = ist_now()

    if (
        not visitor.is_active
        or visitor.expires_at is None
        or visitor.expires_at <= now
    ):
        if visitor.is_active:
            visitor.is_active = 0
            db.commit()
        raise HTTPException(
            403,
            "Visitor access has expired or been deactivated. Please sign in again.",
        )

    if visitor.email_verified_at is None:
        raise HTTPException(403, "Visitor email verification is required.")

    return visitor


# --------------------------------------------------
# OFFICER PROFILE
# --------------------------------------------------

@router.get("/officer/me")
def get_officer_profile(
    officer: OfficerAccount = Depends(get_current_officer),
):
    return {
        "id": officer.id,
        "full_name": officer.full_name,
        "email": officer.email,
        "role": officer.role,
        "location": officer.location,
        "is_active": bool(officer.is_active),
        "email_verified": officer.email_verified_at is not None,
    }


@router.patch("/officer/profile")
def update_officer_profile(
    data: OfficerProfileUpdateRequest,
    officer: OfficerAccount = Depends(get_current_officer),
    db: Session = Depends(get_db),
):
    full_name = data.full_name.strip()
    location = (data.location or "").strip() or None

    if not full_name:
        raise HTTPException(400, "Full name is required.")

    officer.full_name = full_name
    officer.location = location

    try:
        db.commit()
        db.refresh(officer)
    except Exception:
        db.rollback()
        raise HTTPException(500, "Unable to update officer profile.")

    return {
        "message": "Officer profile updated.",
        "id": officer.id,
        "full_name": officer.full_name,
        "email": officer.email,
        "role": officer.role,
        "location": officer.location,
    }


# --------------------------------------------------
# EMPLOYEE DIRECTORY MANAGEMENT
# --------------------------------------------------

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

    if db.query(Employee).filter(Employee.employee_code == employee_code).first():
        raise HTTPException(409, "This employee code already exists.")

    if db.query(Employee).filter(Employee.email == email).first():
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
                "before using your account.\n"
                "Do not share this password."
            ),
        )

        db.commit()
        db.refresh(employee)
    except Exception:
        db.rollback()
        raise HTTPException(
            503,
            "Employee creation or email delivery failed. Check server logs.",
        )

    return {
        "message": "Employee created and temporary password emailed.",
        "employee": {
            "id": employee.id,
            "employee_code": employee.employee_code,
            "full_name": employee.full_name,
            "email": employee.email,
            "is_active": bool(employee.is_active),
            "password_reset_required": bool(employee.password_reset_required),
        },
        "created_by": officer.email,
    }


@router.get("/officers/employees")
def list_employees(
    officer: OfficerAccount = Depends(get_current_officer),
    db: Session = Depends(get_db),
):
    employees = db.query(Employee).order_by(Employee.full_name.asc()).all()

    return {
        "employees": [
            {
                "id": employee.id,
                "employee_code": employee.employee_code,
                "full_name": employee.full_name,
                "email": employee.email,
                "is_active": bool(employee.is_active),
                "password_reset_required": bool(
                    employee.password_reset_required
                ),
            }
            for employee in employees
        ],
        "total": len(employees),
    }


@router.patch("/officers/employees/{employee_id}")
def update_employee(
    employee_id: int,
    data: EmployeeUpdateRequest,
    officer: OfficerAccount = Depends(get_current_officer),
    db: Session = Depends(get_db),
):
    employee = db.get(Employee, employee_id)

    if employee is None:
        raise HTTPException(404, "Employee not found.")

    employee_code = data.employee_code.strip()
    full_name = data.full_name.strip()
    email = normalize_email(data.email)

    duplicate_code = (
        db.query(Employee)
        .filter(
            Employee.employee_code == employee_code,
            Employee.id != employee_id,
        )
        .first()
    )
    duplicate_email = (
        db.query(Employee)
        .filter(
            Employee.email == email,
            Employee.id != employee_id,
        )
        .first()
    )

    if duplicate_code:
        raise HTTPException(409, "This employee code belongs to another employee.")

    if duplicate_email:
        raise HTTPException(409, "This email belongs to another employee.")

    employee.employee_code = employee_code
    employee.full_name = full_name
    employee.email = email

    try:
        db.commit()
        db.refresh(employee)
    except Exception:
        db.rollback()
        raise HTTPException(500, "Unable to update employee.")

    return {
        "message": "Employee details updated.",
        "employee": {
            "id": employee.id,
            "employee_code": employee.employee_code,
            "full_name": employee.full_name,
            "email": employee.email,
            "is_active": bool(employee.is_active),
            "password_reset_required": bool(employee.password_reset_required),
        },
        "updated_by": officer.email,
    }


@router.patch("/officers/employees/{employee_id}/status")
def set_employee_status(
    employee_id: int,
    data: EmployeeStatusRequest,
    officer: OfficerAccount = Depends(get_current_officer),
    db: Session = Depends(get_db),
):
    employee = db.get(Employee, employee_id)

    if employee is None:
        raise HTTPException(404, "Employee not found.")

    employee.is_active = 1 if data.is_active else 0

    try:
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(500, "Unable to update employee status.")

    return {
        "message": "Employee status updated.",
        "employee": {
            "id": employee.id,
            "employee_code": employee.employee_code,
            "full_name": employee.full_name,
            "email": employee.email,
            "is_active": bool(employee.is_active),
        },
        "updated_by": officer.email,
    }


# --------------------------------------------------
# EMPLOYEE LOGIN AND PASSWORD CHANGE
# --------------------------------------------------

@router.post("/employee/login")
def login_employee(
    data: EmployeeLoginRequest,
    db: Session = Depends(get_db),
):
    email = normalize_email(data.email)
    employee = db.query(Employee).filter(Employee.email == email).first()

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


@router.post("/employee/change-password")
def change_employee_password(
    data: EmployeeChangePasswordRequest,
    employee: Employee = Depends(get_current_employee),
    db: Session = Depends(get_db),
):
    if employee.password_reset_required:
        # First login must change the temporary password.
        if not data.current_password:
            raise HTTPException(
                400,
                "Enter your temporary password to set a new password.",
            )
        if not employee.password_hash or not verify_password(
            data.current_password, employee.password_hash
        ):
            raise HTTPException(400, "Current password is incorrect.")
    else:
        if not data.current_password:
            raise HTTPException(400, "Current password is required.")
        if not employee.password_hash or not verify_password(
            data.current_password, employee.password_hash
        ):
            raise HTTPException(400, "Current password is incorrect.")

    if data.current_password == data.new_password:
        raise HTTPException(400, "New password must differ from the current password.")

    employee.password_hash = hash_password(data.new_password)
    employee.password_reset_required = False

    try:
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(500, "Unable to change password.")

    return {
        "message": "Password changed successfully.",
        "password_reset_required": False,
    }


# --------------------------------------------------
# EMPLOYEE FORGOT-PASSWORD FLOW
# --------------------------------------------------

@router.post("/employee/password-reset/request")
def request_employee_password_reset(
    data: PasswordResetRequest,
    db: Session = Depends(get_db),
):
    email = normalize_email(data.email)
    employee = db.query(Employee).filter(Employee.email == email).first()

    # Keep the response generic to avoid disclosing registered emails.
    if employee is None or not employee.is_active:
        return {
            "message": "If an active employee account exists, a reset code will be emailed."
        }

    now = ist_now()
    code = f"{secrets.randbelow(1_000_000):06d}"

    try:
        create_otp_record(
            db, email, "EMPLOYEE_PASSWORD_RESET", code, now
        )
        send_otp_email(
            email,
            employee.full_name,
            code,
            "Reset your Zentry password",
        )
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(503, "Unable to send the password reset code.")

    return {
        "message": "If an active employee account exists, a reset code will be emailed."
    }


@router.post("/employee/password-reset/verify")
def reset_employee_password(
    data: PasswordResetVerifyRequest,
    db: Session = Depends(get_db),
):
    email = normalize_email(data.email)
    employee = db.query(Employee).filter(Employee.email == email).first()

    if employee is None or not employee.is_active:
        raise HTTPException(400, "Invalid reset request.")

    now = ist_now()
    otp_record = validate_otp(
        db,
        email,
        "EMPLOYEE_PASSWORD_RESET",
        data.otp,
        now,
    )

    employee.password_hash = hash_password(data.new_password)
    employee.password_reset_required = False
    otp_record.consumed_at = now

    try:
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(500, "Unable to reset employee password.")

    return {
        "message": "Password reset successfully. Sign in with your new password.",
        "password_reset_required": False,
    }


# --------------------------------------------------
# VISITOR REGISTRATION AND RETURNING VISITORS
# --------------------------------------------------

@router.post("/visitor/register", status_code=201)
def register_visitor(
    data: VisitorRegisterRequest,
    db: Session = Depends(get_db),
):
    email = normalize_email(data.email)
    full_name = data.full_name.strip()

    if not full_name:
        raise HTTPException(400, "Full name is required.")

    now = ist_now()

    # Reuse the latest record for this email; do not create another VRF ID.
    visitor = (
        db.query(Visitor)
        .filter(Visitor.email == email)
        .order_by(Visitor.id.desc())
        .first()
    )

    is_returning_visitor = visitor is not None

    if visitor is None:
        visitor = Visitor(
            vrf_id=next_visitor_vrf_id(db),
            full_name=full_name,
            email=email,
            is_active=0,
            email_verified_at=None,
            expires_at=None,
        )
        db.add(visitor)
    else:
        # Update the name only when a new registration supplies it.
        visitor.full_name = full_name
        # Access is renewed only after successful OTP verification.
        visitor.is_active = 0

    code = f"{secrets.randbelow(1_000_000):06d}"

    try:
        create_otp_record(db, email, "VISITOR_REGISTER", code, now)
        db.flush()

        send_email(
            recipient=email,
            subject="Your Zentry visitor verification code",
            body=(
                f"Hello {full_name},\n\n"
                f"Your Zentry visitor ID is: {visitor.vrf_id}\n"
                f"Your verification code is: {code}\n\n"
                "The code expires in 10 minutes. After successful verification, "
                "your visitor access lasts up to 9 hours.\n"
                "If you did not request this, ignore this email."
            ),
        )
        db.commit()
        db.refresh(visitor)
    except Exception:
        db.rollback()
        raise HTTPException(
            503,
            "Visitor registration or email delivery failed. Check server email configuration.",
        )

    return {
        "message": (
            "Returning visitor found. Verify your email to renew access."
            if is_returning_visitor
            else "Visitor registration created. Check your email for the OTP."
        ),
        "vrf_id": visitor.vrf_id,
        "email": email,
        "verification_required": True,
        "returning_visitor": is_returning_visitor,
    }


@router.post("/visitor/verify-email")
def verify_visitor_email(
    data: VisitorVerifyRequest,
    db: Session = Depends(get_db),
):
    email = normalize_email(data.email)
    vrf_id = data.vrf_id.strip().upper()
    now = ist_now()

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

    otp_record = validate_otp(
        db, email, "VISITOR_REGISTER", data.otp, now
    )

    visitor.email_verified_at = now
    visitor.is_active = 1
    visitor.expires_at = now + timedelta(hours=VISITOR_ACCESS_HOURS)
    visitor.last_login_at = now
    otp_record.consumed_at = now

    try:
        db.commit()
        db.refresh(visitor)
    except Exception:
        db.rollback()
        raise HTTPException(500, "Unable to verify visitor registration.")

    return {
        "message": "Visitor verified successfully. Access lasts up to 9 hours.",
        "access_token": issue_visitor_token(visitor),
        "token_type": "bearer",
        "account": visitor_account_data(visitor),
    }


# --------------------------------------------------
# EXISTING VISITOR LOGIN WITH EMAIL OTP
# --------------------------------------------------

@router.post("/visitor/login/request-otp")
def request_visitor_login_otp(
    data: VisitorLoginRequest,
    db: Session = Depends(get_db),
):
    email = normalize_email(data.email)

    visitor = (
        db.query(Visitor)
        .filter(Visitor.email == email)
        .order_by(Visitor.id.desc())
        .first()
    )

    if visitor is None or visitor.email_verified_at is None:
        # Do not silently create an account through the login endpoint.
        raise HTTPException(
            404,
            "Verified visitor account not found. Choose New Visitor registration.",
        )

    now = ist_now()
    code = f"{secrets.randbelow(1_000_000):06d}"

    try:
        create_otp_record(db, email, "VISITOR_LOGIN", code, now)
        send_otp_email(
            email,
            visitor.full_name,
            code,
            "Your Zentry visitor login code",
        )
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(503, "Unable to send visitor login code.")

    return {
        "message": "Login code sent to your registered email.",
        "email": email,
    }


@router.post("/visitor/login/verify-otp")
def verify_visitor_login_otp(
    data: VisitorLoginVerifyRequest,
    db: Session = Depends(get_db),
):
    email = normalize_email(data.email)
    now = ist_now()

    visitor = (
        db.query(Visitor)
        .filter(Visitor.email == email)
        .order_by(Visitor.id.desc())
        .first()
    )

    if visitor is None or visitor.email_verified_at is None:
        raise HTTPException(404, "Verified visitor account not found.")

    otp_record = validate_otp(
        db, email, "VISITOR_LOGIN", data.otp, now
    )

    # Successful OTP renews the nine-hour visitor session.
    visitor.is_active = 1
    visitor.expires_at = now + timedelta(hours=VISITOR_ACCESS_HOURS)
    visitor.last_login_at = now
    otp_record.consumed_at = now

    try:
        db.commit()
        db.refresh(visitor)
    except Exception:
        db.rollback()
        raise HTTPException(500, "Unable to complete visitor login.")

    return {
        "message": "Visitor login successful.",
        "access_token": issue_visitor_token(visitor),
        "token_type": "bearer",
        "account": visitor_account_data(visitor),
    }


# --------------------------------------------------
# VISITOR DIRECTORY AND STATUS MANAGEMENT
# --------------------------------------------------

@router.get("/officers/visitors")
def list_visitors(
    officer: OfficerAccount = Depends(get_current_officer),
    db: Session = Depends(get_db),
):
    now = ist_now()

    visitors = db.query(Visitor).order_by(Visitor.id.desc()).all()

    # Expire stale visitor access while building the directory.
    changed = False
    result = []

    for visitor in visitors:
        if (
            visitor.is_active
            and (
                visitor.expires_at is None
                or visitor.expires_at <= now
            )
        ):
            visitor.is_active = 0
            changed = True

        result.append({
            "id": visitor.id,
            "vrf_id": visitor.vrf_id,
            "full_name": visitor.full_name,
            "email": visitor.email,
            "is_active": bool(visitor.is_active),
            "email_verified": visitor.email_verified_at is not None,
"created_at": ist_iso(visitor.created_at),
"expires_at": ist_iso(visitor.expires_at),
"last_login_at": ist_iso(visitor.last_login_at),
        })

    if changed:
        db.commit()

    return {"visitors": result, "total": len(result)}


@router.patch("/officers/visitors/{visitor_id}/status")
def set_visitor_status(
    visitor_id: int,
    data: VisitorStatusRequest,
    officer: OfficerAccount = Depends(get_current_officer),
    db: Session = Depends(get_db),
):
    visitor = db.get(Visitor, visitor_id)

    if visitor is None:
        raise HTTPException(404, "Visitor not found.")

    if data.is_active:
        if visitor.email_verified_at is None:
            raise HTTPException(
                400,
                "An unverified visitor cannot be activated. Verify their email first.",
            )

        if visitor.expires_at is None or visitor.expires_at <= ist_now():
            raise HTTPException(
                400,
                "Visitor access has expired. The visitor must sign in again to renew access.",
            )

    visitor.is_active = 1 if data.is_active else 0

    try:
        db.commit()
        db.refresh(visitor)
    except Exception:
        db.rollback()
        raise HTTPException(500, "Unable to update visitor status.")

    return {
        "message": "Visitor status updated.",
        "visitor": visitor_account_data(visitor),
        "updated_by": officer.email,
    }
