"""
Domain models for the electronics recycling system.

These plain data classes represent entities stored in the database.  They
encapsulate only data, leaving behaviour to the service layer.  Keeping
models simple follows the **KISS** principle by avoiding
unnecessary complexity.  Should additional behaviour be required in the
future, new service classes can be introduced without modifying the models
themselves (an application of the **Single Responsibility Principle**).
"""
from dataclasses import dataclass
from datetime import datetime


@dataclass
class Client:
    id: int
    name: str
    contact_info: str


@dataclass
class DeviceType:
    id: int
    name: str
    description: str


@dataclass
class SubmittedDevice:
    id: int
    client_id: int
    device_type_id: int
    submitted_at: datetime


@dataclass
class InspectionResult:
    id: int
    submitted_device_id: int
    inspector_id: int
    condition: str
    notes: str


@dataclass
class FinalOffer:
    id: int
    submitted_device_id: int
    final_price: float
    decision: str  # e.g. "recycle" or "resell"


@dataclass
class Payment:
    id: int
    final_offer_id: int
    amount: float
    payment_date: datetime
    status: str  # e.g. "pending", "paid"


@dataclass
class PartnerTransfer:
    id: int
    final_offer_id: int
    partner_type: str  # e.g. "recycle", "resell"
    transfer_date: datetime
    status: str  # e.g. "pending", "sent"