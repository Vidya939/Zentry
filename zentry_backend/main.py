#D:\App_Dvpt\zentry\zentry_backend\main.py:
import json
from datetime import date, datetime, time, timedelta
from typing import Generator, Literal

from fastapi import Depends, FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, ConfigDict, Field, field_serializer
from sqlalchemy.orm import Session

from auth_routes import (
    get_current_employee,
    get_current_officer,
    get_current_visitor,
    router as auth_router,
)
from database import SessionLocal, ist_now, ist_iso
from models import (
    Employee,
    Incident,
    IncidentAuditLog,
    IncidentResponse as IncidentResponseModel,
    OfficerAccount,
    Visitor,
)

app = FastAPI(
    title="Zentry API",
    description="Backend API for the Zentry employee safety system",
    version="1.1.0",
)

app.include_router(auth_router)

# Development configuration. Restrict CORS origins before production.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def utcnow() -> datetime:
    return ist_now()


class IncidentCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    message: str = Field(min_length=1)
    location: str = Field(min_length=1, max_length=200)

class IncidentOutput(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    title: str
    message: str
    location: str
    status: str
    created_by: str
    created_at: datetime
    cleared_at: datetime | None = None

    @field_serializer("created_at", "cleared_at", when_used="json")
    def serialize_incident_timestamps(
        self, value: datetime | None
    ) -> str | None:
        return ist_iso(value)


class ResponseCreate(BaseModel):
    response_status: Literal[
        "SAFE_AT_ASSEMBLY",
        "SAFE_OUTSIDE",
        "SAFE_INSIDE",
        "NEED_HELP",
    ]
    message: str | None = Field(default=None, max_length=2000)
    location_details: str | None = Field(default=None, max_length=500)
    condition_status: Literal["INJURED", "NOT_INJURED"] | None = None
    evacuation_status: Literal["COMPLETED", "NOT_COMPLETED"] | None = None


class EmployeeResponseCreate(ResponseCreate):
    pass


class VisitorResponseCreate(ResponseCreate):
    pass


SAFE_RESPONSE_STATUSES = {"SAFE_AT_ASSEMBLY", "SAFE_OUTSIDE"}
ALL_RESPONSE_STATUSES = {
    "SAFE_AT_ASSEMBLY",
    "SAFE_OUTSIDE",
    "SAFE_INSIDE",
    "NEED_HELP",
}


def get_incident_or_404(db: Session, incident_id: int) -> Incident:
    incident = db.get(Incident, incident_id)
    if incident is None:
        raise HTTPException(status_code=404, detail="Incident not found")
    return incident


def write_audit_log(
    db: Session,
    incident_id: int,
    officer: OfficerAccount,
    action: str,
    details: dict | None = None,
) -> None:
    """Record officer actions using the existing incident audit table."""
    db.add(
        IncidentAuditLog(
            incident_id=incident_id,
            actor_type="officer",
            actor_id=officer.id,
            action=action,
            details=json.dumps(details or {}),
        )
    )


def get_expected_people_and_responses(db: Session, incident_id: int):
    """Get active employees, eligible visitors and their incident responses."""
    now = utcnow()

    employees = (
        db.query(Employee)
        .filter(Employee.is_active == 1)
        .order_by(Employee.full_name.asc())
        .all()
    )

    visitors = (
        db.query(Visitor)
        .filter(
            Visitor.is_active == 1,
            Visitor.email_verified_at.isnot(None),
            Visitor.expires_at > now,
        )
        .order_by(Visitor.full_name.asc())
        .all()
    )

    records = (
        db.query(IncidentResponseModel)
        .filter(IncidentResponseModel.incident_id == incident_id)
        .all()
    )

    employee_responses = {
        record.employee_id: record
        for record in records
        if record.employee_id is not None
    }
    visitor_responses = {
        record.visitor_id: record
        for record in records
        if record.visitor_id is not None
    }

    return employees, visitors, employee_responses, visitor_responses


def person_response(
    account_type: str,
    person,
    record: IncidentResponseModel | None,
) -> dict:
    is_visitor = account_type == "visitor"
    status = record.response_status if record else "NO_RESPONSE"

    return {
        "account_type": account_type,
        "person_id": person.id,
        "name": person.full_name,
        "identifier": person.vrf_id if is_visitor else person.employee_code,
        "employee_id": None if is_visitor else person.id,
        "visitor_id": person.id if is_visitor else None,
        "employee_code": None if is_visitor else person.employee_code,
        "visitor_vrf_id": person.vrf_id if is_visitor else None,
        "email": person.email,
        "response_status": status,
        "message": record.message if record else None,
        "location_details": record.location_details if record else None,
        "condition_status": record.condition_status if record else None,
        "evacuation_status": record.evacuation_status if record else None,
"responded_at": ist_iso(record.responded_at) if record else None,
"updated_at": ist_iso(record.updated_at) if record else None,
"dispatched_at": ist_iso(record.dispatched_at) if record else None,
"located_at": ist_iso(record.located_at) if record else None,
        "located": bool(record and record.located_at),
        "warden_dispatched": bool(record and record.dispatched_at),
    }


def get_all_expected_people(db: Session, incident_id: int) -> list[dict]:
    employees, visitors, employee_responses, visitor_responses = (
        get_expected_people_and_responses(db, incident_id)
    )

    people = [
        person_response(
            "employee",
            employee,
            employee_responses.get(employee.id),
        )
        for employee in employees
    ]
    people.extend(
        person_response(
            "visitor",
            visitor,
            visitor_responses.get(visitor.id),
        )
        for visitor in visitors
    )
    return people


def get_incident_clearance_blockers(
    db: Session,
    incident_id: int,
) -> tuple[int, list[dict]]:
    """Every expected person must explicitly confirm an acceptable safe status."""
    people = get_all_expected_people(db, incident_id)
    blockers = []

    for person in people:
        status = person["response_status"]

        if status in SAFE_RESPONSE_STATUSES:
            continue

        if status == "NO_RESPONSE":
            reason = "No response received."
        elif status == "SAFE_INSIDE":
            reason = "Person has reported being inside."
        elif status == "NEED_HELP":
            reason = (
                "Help request is unresolved. Being located does not "
                "automatically mean the person is safe."
            )
        else:
            reason = "Person has not confirmed a safe status."

        blockers.append(
            {
                **person,
                "reason": reason,
            }
        )

    return len(people), blockers


def get_or_create_response(
    db: Session,
    incident_id: int,
    account_type: str,
    person_id: int,
) -> IncidentResponseModel:
    query = db.query(IncidentResponseModel).filter(
        IncidentResponseModel.incident_id == incident_id
    )

    if account_type == "employee":
        person = (
            db.query(Employee)
            .filter(Employee.id == person_id, Employee.is_active == 1)
            .first()
        )
        if person is None:
            raise HTTPException(status_code=404, detail="Active employee not found")
        record = query.filter(
            IncidentResponseModel.employee_id == person_id
        ).first()
        if record is None:
            record = IncidentResponseModel(
                incident_id=incident_id,
                employee_id=person_id,
                response_status="NO_RESPONSE",
            )
            db.add(record)
        return record

    person = (
        db.query(Visitor)
        .filter(
            Visitor.id == person_id,
            Visitor.is_active == 1,
            Visitor.email_verified_at.isnot(None),
            Visitor.expires_at > utcnow(),
        )
        .first()
    )
    if person is None:
        raise HTTPException(status_code=404, detail="Active visitor not found")

    record = query.filter(
        IncidentResponseModel.visitor_id == person_id
    ).first()
    if record is None:
        record = IncidentResponseModel(
            incident_id=incident_id,
            visitor_id=person_id,
            response_status="NO_RESPONSE",
        )
        db.add(record)

    return record


def save_response(
    db: Session,
    incident_id: int,
    account_type: str,
    person,
    data: ResponseCreate,
) -> dict:
    incident = get_incident_or_404(db, incident_id)

    if incident.status != "ACTIVE":
        raise HTTPException(
            status_code=409,
            detail="This incident is no longer active.",
        )

    try:
        query = db.query(IncidentResponseModel).filter(
            IncidentResponseModel.incident_id == incident_id
        )

        if account_type == "employee":
            record = query.filter(
                IncidentResponseModel.employee_id == person.id
            ).first()
        else:
            record = query.filter(
                IncidentResponseModel.visitor_id == person.id
            ).first()

        now = utcnow()

        if record is None:
            values = {
                "incident_id": incident_id,
                "response_status": data.response_status,
                "message": data.message,
                "location_details": data.location_details,
                "condition_status": data.condition_status,
                "evacuation_status": data.evacuation_status,
                "responded_at": now,
            }
            if account_type == "employee":
                values["employee_id"] = person.id
            else:
                values["visitor_id"] = person.id

            record = IncidentResponseModel(**values)
            db.add(record)
        else:
            record.response_status = data.response_status
            record.message = data.message
            record.location_details = data.location_details
            record.condition_status = data.condition_status
            record.evacuation_status = data.evacuation_status
            # Preserve the first response timestamp.
            if record.responded_at is None:
                record.responded_at = now

        db.commit()
        db.refresh(record)

        return {
            "message": f"{account_type.title()} response saved",
            "incident_id": incident_id,
            "account_type": account_type,
            "person_id": person.id,
            "name": person.full_name,
            "identifier": (
                person.vrf_id if account_type == "visitor"
                else person.employee_code
            ),
            "response_status": record.response_status,
            "location_details": record.location_details,
            "condition_status": record.condition_status,
            "evacuation_status": record.evacuation_status,
"responded_at": ist_iso(record.responded_at),
"updated_at": ist_iso(record.updated_at),
        }
    except HTTPException:
        db.rollback()
        raise
    except Exception as exc:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Unable to save the response. Check backend logs.",
        ) from exc


@app.get("/")
def home():
    return {
        "application": "Zentry API",
        "message": "Backend is running",
        "status": "success",
    }


@app.get("/health")
def health_check():
    return {"status": "healthy"}


@app.post("/incidents", response_model=IncidentOutput, status_code=201)
def create_incident(
    data: IncidentCreate,
    officer=Depends(get_current_officer),
    db: Session = Depends(get_db),
):
    active = (
        db.query(Incident)
        .filter(Incident.status == "ACTIVE")
        .first()
    )
    if active:
        raise HTTPException(
            status_code=409,
            detail=f"Incident #{active.id} is already active. Clear it first.",
        )

    incident = Incident(
        title=data.title.strip(),
        message=data.message.strip(),
        location=data.location.strip(),
        created_by=officer.full_name,
        status="ACTIVE",
    )

    try:
        db.add(incident)
        db.flush()
        write_audit_log(
            db,
            incident.id,
            officer,
            "INCIDENT_CREATED",
            {
                "title": incident.title,
                "location": incident.location,
            },
        )
        db.commit()
        db.refresh(incident)
        return incident
    except Exception as exc:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Unable to save incident to the database.",
        ) from exc


@app.get("/incidents", response_model=list[IncidentOutput])
def get_incidents(
    from_date: date | None = Query(default=None),
    to_date: date | None = Query(default=None),
    officer=Depends(get_current_officer),
    db: Session = Depends(get_db),
):
    if from_date and to_date and from_date > to_date:
        raise HTTPException(
            status_code=422,
            detail="from_date must be on or before to_date.",
        )

    query = db.query(Incident)

    if from_date:
        query = query.filter(
            Incident.created_at >= datetime.combine(from_date, time.min)
        )
    if to_date:
        query = query.filter(
            Incident.created_at
            < datetime.combine(to_date + timedelta(days=1), time.min)
        )

    return query.order_by(Incident.created_at.desc(), Incident.id.desc()).all()


@app.get("/incidents/active", response_model=list[IncidentOutput])
def get_active_incidents(db: Session = Depends(get_db)):
    return (
        db.query(Incident)
        .filter(Incident.status == "ACTIVE")
        .order_by(Incident.id.desc())
        .all()
    )


def get_last_drill_for_person(
    db: Session,
    account_type: str,
    person_id: int,
):
    incident = (
        db.query(Incident)
        .filter(
            Incident.status == "CLEARED",
            Incident.cleared_at.isnot(None),
        )
        .order_by(
            Incident.cleared_at.desc(),
            Incident.id.desc(),
        )
        .first()
    )

    if incident is None:
        return None

    query = db.query(IncidentResponseModel).filter(
        IncidentResponseModel.incident_id == incident.id
    )

    if account_type == "visitor":
        response = query.filter(
            IncidentResponseModel.visitor_id == person_id
        ).first()
    else:
        response = query.filter(
            IncidentResponseModel.employee_id == person_id
        ).first()

    responded_at = response.responded_at if response else None

    duration_seconds = None
    if responded_at is not None:
        duration_seconds = max(
            0,
            int((responded_at - incident.created_at).total_seconds()),
        )

    return {
        "incident_id": incident.id,
        "title": incident.title,
        "status": incident.status,
        "created_at": ist_iso(incident.created_at),
        "cleared_at": ist_iso(incident.cleared_at),
        "responded_at": ist_iso(responded_at),
        "response_status": (
            response.response_status if response else "NO_RESPONSE"
        ),
        "response_duration_seconds": duration_seconds,
    }


@app.get("/incidents/last-drill/employee")
def get_employee_last_drill(
    employee: Employee = Depends(get_current_employee),
    db: Session = Depends(get_db),
):
    return get_last_drill_for_person(
        db, "employee", employee.id
    )


@app.get("/incidents/last-drill/visitor")
def get_visitor_last_drill(
    visitor: Visitor = Depends(get_current_visitor),
    db: Session = Depends(get_db),
):
    return get_last_drill_for_person(
        db, "visitor", visitor.id
    )


@app.post("/incidents/{incident_id}/responses")
def submit_employee_response(
    incident_id: int,
    data: EmployeeResponseCreate,
    employee: Employee = Depends(get_current_employee),
    db: Session = Depends(get_db),
):
    return save_response(db, incident_id, "employee", employee, data)


@app.post("/incidents/{incident_id}/visitor-responses")
def submit_visitor_response(
    incident_id: int,
    data: VisitorResponseCreate,
    visitor: Visitor = Depends(get_current_visitor),
    db: Session = Depends(get_db),
):
    return save_response(db, incident_id, "visitor", visitor, data)


@app.get("/incidents/{incident_id}/people")
def get_incident_people(
    incident_id: int,
    officer=Depends(get_current_officer),
    db: Session = Depends(get_db),
):
    incident = get_incident_or_404(db, incident_id)
    people = get_all_expected_people(db, incident_id)

    return {
        "incident_id": incident.id,
        "incident_status": incident.status,
        "expected": len(people),
        "people": people,
        "no_response_people": [
            person for person in people
            if person["response_status"] == "NO_RESPONSE"
        ],
        "help_requested_people": [
            person for person in people
            if person["response_status"] == "NEED_HELP"
        ],
        "safe_inside_people": [
            person for person in people
            if person["response_status"] == "SAFE_INSIDE"
        ],
    }


@app.get("/incidents/{incident_id}/summary")
def get_incident_summary(
    incident_id: int,
    officer=Depends(get_current_officer),
    db: Session = Depends(get_db),
):
    incident = get_incident_or_404(db, incident_id)
    people = get_all_expected_people(db, incident_id)

    counts = {
        "SAFE_AT_ASSEMBLY": 0,
        "SAFE_OUTSIDE": 0,
        "SAFE_INSIDE": 0,
        "NEED_HELP": 0,
        "NO_RESPONSE": 0,
    }
    for person in people:
        status = person["response_status"]
        counts[status] = counts.get(status, 0) + 1

    responded = len(people) - counts["NO_RESPONSE"]

    return {
        "incident_id": incident.id,
        "title": incident.title,
        "status": incident.status,
"created_at": ist_iso(incident.created_at),
"cleared_at": ist_iso(incident.cleared_at),
        "expected": len(people),
        "responded": responded,
        "no_response": counts["NO_RESPONSE"],
        "at_assembly": counts["SAFE_AT_ASSEMBLY"],
        "safe_elsewhere": counts["SAFE_OUTSIDE"],
        "safe_inside": counts["SAFE_INSIDE"],
        "help_requested": counts["NEED_HELP"],
        "safe_confirmed": counts["SAFE_AT_ASSEMBLY"] + counts["SAFE_OUTSIDE"],
    }


@app.get("/incidents/{incident_id}/responses")
def get_incident_responses(
    incident_id: int,
    officer=Depends(get_current_officer),
    db: Session = Depends(get_db),
):
    get_incident_or_404(db, incident_id)
    return get_all_expected_people(db, incident_id)


@app.post("/incidents/{incident_id}/people/{account_type}/{person_id}/dispatch")
def dispatch_warden(
    incident_id: int,
    account_type: Literal["employee", "visitor"],
    person_id: int,
    officer=Depends(get_current_officer),
    db: Session = Depends(get_db),
):
    incident = get_incident_or_404(db, incident_id)
    if incident.status != "ACTIVE":
        raise HTTPException(status_code=409, detail="Incident is not active.")

    record = None
    try:
        record = get_or_create_response(
            db, incident_id, account_type, person_id
        )
        record.assigned_to_officer_id = officer.id
        record.dispatched_at = utcnow()

        write_audit_log(
            db,
            incident_id,
            officer,
            "WARDEN_DISPATCHED",
            {
                "account_type": account_type,
                "person_id": person_id,
            },
        )
        db.commit()
        db.refresh(record)

        return {
            "message": "Warden dispatch recorded.",
            "incident_id": incident_id,
            "account_type": account_type,
            "person_id": person_id,
            "assigned_to_officer_id": officer.id,
            "dispatched_at": ist_iso(record.dispatched_at),
            "response_status": record.response_status,
        }
    except HTTPException:
        db.rollback()
        raise
    except Exception as exc:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Unable to record warden dispatch.",
        ) from exc


@app.post("/incidents/{incident_id}/people/{account_type}/{person_id}/located")
def mark_person_located(
    incident_id: int,
    account_type: Literal["employee", "visitor"],
    person_id: int,
    officer=Depends(get_current_officer),
    db: Session = Depends(get_db),
):
    incident = get_incident_or_404(db, incident_id)
    if incident.status != "ACTIVE":
        raise HTTPException(status_code=409, detail="Incident is not active.")

    try:
        record = get_or_create_response(
            db, incident_id, account_type, person_id
        )
        record.located_at = utcnow()

        write_audit_log(
            db,
            incident_id,
            officer,
            "PERSON_MARKED_LOCATED",
            {
                "account_type": account_type,
                "person_id": person_id,
                "response_status": record.response_status,
            },
        )
        db.commit()
        db.refresh(record)

        return {
            "message": (
                "Person marked as located. Their safety status has not "
                "been changed."
            ),
            "incident_id": incident_id,
            "account_type": account_type,
            "person_id": person_id,
            "located_at": ist_iso(record.located_at),
            "response_status": record.response_status,
        }
    except HTTPException:
        db.rollback()
        raise
    except Exception as exc:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Unable to mark person as located.",
        ) from exc


@app.post("/incidents/{incident_id}/clear")
def clear_incident(
    incident_id: int,
    officer=Depends(get_current_officer),
    db: Session = Depends(get_db),
):
    incident = get_incident_or_404(db, incident_id)

    if incident.status != "ACTIVE":
        raise HTTPException(
            status_code=409,
            detail="This incident has already been cleared.",
        )

    expected_count, blockers = get_incident_clearance_blockers(
        db, incident_id
    )

    if blockers:
        raise HTTPException(
            status_code=409,
            detail={
                "message": (
                    "All Clear is blocked. Every expected person must "
                    "confirm SAFE_AT_ASSEMBLY or SAFE_OUTSIDE. A dispatch "
                    "or located marker does not count as a safety confirmation."
                ),
                "incident_id": incident.id,
                "expected_people": expected_count,
                "blocked_count": len(blockers),
                "blocked_people": blockers,
            },
        )

    try:
        incident.status = "CLEARED"
        incident.cleared_at = utcnow()

        write_audit_log(
            db,
            incident_id,
            officer,
            "INCIDENT_CLEARED",
            {"expected_people": expected_count},
        )
        db.commit()
        db.refresh(incident)
    except Exception as exc:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Unable to clear the incident. Please try again.",
        ) from exc

    return {
        "message": "Incident marked as cleared.",
        "incident_id": incident.id,
        "status": incident.status,
        "cleared_at": ist_iso(incident.cleared_at),
    }