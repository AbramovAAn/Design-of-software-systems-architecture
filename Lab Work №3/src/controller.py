"""
API controller layer.

The controller exposes a method that simulates receiving a request from
an inspector.  It delegates the business logic to the service layer
without any processing of its own, keeping it slim and adhering to
the **KISS** principle.  It accepts a dictionary representing the
request and returns a dictionary representing the response, making it
simple to test or integrate.
"""
from __future__ import annotations
from datetime import UTC, datetime
from typing import Any, Dict

from .services import InspectionService
from .models import SubmittedDevice


class InspectionController:
    """Controller for handling device inspection requests."""

    def __init__(self, inspection_service: InspectionService) -> None:
        self.inspection_service = inspection_service

    def inspect_device(self, request_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Simulate an HTTP endpoint that receives inspection data from a client.
        Only extracts relevant fields and delegates work to the service.
        """
        # Extract and validate input (minimal validation for brevity)
        submitted_device = SubmittedDevice(
            id=request_data["device_id"],
            client_id=request_data["client_id"],
            device_type_id=request_data["device_type_id"],
            submitted_at=request_data.get("submitted_at", datetime.now(UTC)),
        )
        inspector_id = request_data["inspector_id"]
        condition = request_data["condition"]
        notes = request_data.get("notes", "")

        # Delegate to service layer
        final_offer = self.inspection_service.perform_inspection(
            submitted_device,
            inspector_id=inspector_id,
            condition=condition,
            notes=notes,
        )

        # Build response
        response = {
            "submitted_device_id": final_offer.submitted_device_id,
            "final_price": final_offer.final_price,
            "decision": final_offer.decision,
        }
        return response
