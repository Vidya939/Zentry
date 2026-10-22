from auth_routes import (
    router as auth_router,
    get_current_employee,
    get_current_visitor,
)
from datetime import datetime
from typing import Generator, Literal

from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.orm import Session

from database import SessionLocal
from models import (
    Employee,
    Visitor,
    Incident,
    IncidentResponse as IncidentResponseModel,
)

app = FastAPI(
    title="Zentry API",
    description="Backend API for the Zentry employee safety system",
    version="1.0.0",
)
app.include_router(auth_router)

# Local development only. Restrict origins before production.
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


class IncidentCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    message: str = Field(min_length=1)
    location: str = Field(min_length=1, max_length=200)
    created_by: str = Field(min_length=1, max_length=120)


class IncidentOutput(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    title: str
    message: str
    location: str
    status: str
    created_by: str
    created_at: datetime


class EmployeeResponseCreate(BaseModel):
    response_status: Literal[
        "SAFE_AT_ASSEMBLY",
        "SAFE_OUTSIDE",
        "SAFE_INSIDE",
        "NEED_HELP",
    ]
    message: str | None = None

class VisitorResponseCreate(BaseModel):
    response_status: Literal[
        "SAFE_AT_ASSEMBLY",
        "SAFE_OUTSIDE",
        "SAFE_INSIDE",
        "NEED_HELP",
    ]
    message: str | None = None
    location_details: str | None = Field(
        default=None,
        max_length=500,
    )

def get_incident_or_404(db: Session, incident_id: int) -> Incident:
    incident = db.get(Incident, incident_id)
    if incident is None:
        raise HTTPException(status_code=404, detail="Incident not found")
    return incident


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
    db: Session = Depends(get_db),
):
    # Prevent a second incident while one is already active.
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
        created_by=data.created_by.strip(),
        status="ACTIVE",
    )

    try:
        db.add(incident)
        db.commit()
        db.refresh(incident)
        return incident
    except Exception:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Unable to save incident to the database.",
        )


@app.get("/incidents", response_model=list[IncidentOutput])
def get_incidents(db: Session = Depends(get_db)):
    return db.query(Incident).order_by(Incident.id.desc()).all()


@app.get("/incidents/active", response_model=list[IncidentOutput])
def get_active_incidents(db: Session = Depends(get_db)):
    return (
        db.query(Incident)
        .filter(Incident.status == "ACTIVE")
        .order_by(Incident.id.desc())
        .all()
    )


@app.post("/incidents/{incident_id}/responses")
def submit_response(
    incident_id: int,
    data: EmployeeResponseCreate,
    employee: Employee = Depends(get_current_employee),
    db: Session = Depends(get_db),
):
    incident = get_incident_or_404(db, incident_id)

    if incident.status != "ACTIVE":
        raise HTTPException(
            status_code=409,
            detail="This incident is no longer active.",
        )

    try:
        response_record = (
            db.query(IncidentResponseModel)
            .filter(
                IncidentResponseModel.incident_id == incident_id,
                IncidentResponseModel.employee_id == employee.id,
            )
            .first()
        )

        if response_record is None:
            response_record = IncidentResponseModel(
                incident_id=incident_id,
                employee_id=employee.id,
                response_status=data.response_status,
                message=data.message,
            )
            db.add(response_record)
        else:
            response_record.response_status = data.response_status
            response_record.message = data.message

        db.commit()
        db.refresh(response_record)

        return {
            "message": "Employee response saved",
            "incident_id": incident_id,
            "employee_id": employee.id,
            "employee_name": employee.full_name,
            "response_status": response_record.response_status,
            "updated_at": response_record.updated_at,
        }

    except Exception:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail="Unable to save the employee response.",
        )


@app.get("/incidents/{incident_id}/summary")
def get_incident_summary(
    incident_id: int,
    db: Session = Depends(get_db),
):
    incident = get_incident_or_404(db, incident_id)

    expected = (
        db.query(Employee)
        .filter(Employee.is_active == 1)
        .count()
    )

    records = (
        db.query(IncidentResponseModel)
        .filter(IncidentResponseModel.incident_id == incident_id)
        .all()
    )

    counts = {
        "SAFE_AT_ASSEMBLY": 0,
        "SAFE_OUTSIDE": 0,
        "SAFE_INSIDE": 0,
        "NEED_HELP": 0,
    }

    for record in records:
        if record.response_status in counts:
            counts[record.response_status] += 1

    responded = sum(counts.values())

    return {
        "incident_id": incident.id,
        "title": incident.title,
        "status": incident.status,
        "expected": expected,
        "responded": responded,
        "no_response": max(expected - responded, 0),
        "at_assembly": counts["SAFE_AT_ASSEMBLY"],
        "safe_elsewhere": counts["SAFE_OUTSIDE"],
        "safe_inside": counts["SAFE_INSIDE"],
        "help_requested": counts["NEED_HELP"],
    }


@app.get("/incidents/{incident_id}/responses")
def get_incident_responses(
    incident_id: int,
    db: Session = Depends(get_db),
):
    get_incident_or_404(db, incident_id)

    records = (
        db.query(IncidentResponseModel)
        .filter(IncidentResponseModel.incident_id == incident_id)
        .all()
    )

    responses = []

    for record in records:
        employee = record.employee
        visitor = record.visitor

        responses.append({
            "employee_code": (
                employee.employee_code if employee else None
            ),
            "employee_name": (
                employee.full_name if employee else None
            ),
            "visitor_vrf_id": (
                visitor.vrf_id if visitor else None
            ),
            "visitor_name": (
                visitor.full_name if visitor else None
            ),
            "account_type": (
                "visitor" if visitor else "employee"
            ),
            "response_status": record.response_status,
            "message": record.message,
            "updated_at": record.updated_at,
        })

    return responses

@app.post("/incidents/{incident_id}/clear")
def clear_incident(
    incident_id: int,
    db: Session = Depends(get_db),
):
    incident = get_incident_or_404(db, incident_id)

    if incident.status != "ACTIVE":
        raise HTTPException(
            status_code=409,
            detail="This incident has already been cleared.",
        )

    incident.status = "CLEARED"
    db.commit()
    db.refresh(incident)

    return {
        "message": "Incident marked as cleared",
        "incident_id": incident.id,
        "status": incident.status,
    }

@app.post("/incidents/{incident_id}/visitor-responses")
def submit_visitor_response(
    incident_id: int,
    data: VisitorResponseCreate,
    visitor: Visitor = Depends(get_current_visitor),
    db: Session = Depends(get_db),
):
    incident = get_incident_or_404(db, incident_id)

    if incident.status != "ACTIVE":
        raise HTTPException(
            status_code=409,
            detail="This incident is no longer active.",
        )

    try:
        response_record = (
            db.query(IncidentResponseModel)
            .filter(
                IncidentResponseModel.incident_id == incident_id,
                IncidentResponseModel.visitor_id == visitor.id,
            )
            .first()
        )

        if response_record is None:
            response_record = IncidentResponseModel(
                incident_id=incident_id,
                visitor_id=visitor.id,
                response_status=data.response_status,
                message=data.message,
                location_details=data.location_details,
            )
            db.add(response_record)
        else:
            response_record.response_status = data.response_status
            response_record.message = data.message
            response_record.location_details = data.location_details

        db.commit()
        db.refresh(response_record)

        return {
            "message": "Visitor response saved successfully.",
            "incident_id": incident_id,
            "visitor_id": visitor.id,
            "vrf_id": visitor.vrf_id,
            "visitor_name": visitor.full_name,
            "response_status": response_record.response_status,
            "location_details": response_record.location_details,
            "updated_at": response_record.updated_at,
        }

    except Exception as exc:
        db.rollback()

        if isinstance(exc, HTTPException):
            raise

        raise HTTPException(
            status_code=500,
            detail="Unable to save the visitor response.",
        )