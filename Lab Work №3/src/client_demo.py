"""
Demonstration script for the inspection and offer flow.

This script assembles the components of the system – repository, gateways,
services, and controller – then simulates a single device inspection.  It
illustrates the simple, linear flow described in the sequence diagram and
exercises the principles of KISS, YAGNI, DRY and SOLID implemented in
``lab3_code``.  Running this module will print the outcome of the
inspection to the console along with messages from the mock gateways.
"""
from __future__ import annotations

from datetime import UTC, datetime
import sys
from pathlib import Path

try:
    from .repositories import InMemoryInspectionRepository
    from .gateways import ConsolePaymentGateway, ConsolePartnerGateway
    from .services import OfferService, InspectionService
    from .controller import InspectionController
except ImportError:  # Allows direct script execution: python lab3_code/client_demo.py
    sys.path.append(str(Path(__file__).resolve().parent.parent))
    from lab3_code.repositories import InMemoryInspectionRepository
    from lab3_code.gateways import ConsolePaymentGateway, ConsolePartnerGateway
    from lab3_code.services import OfferService, InspectionService
    from lab3_code.controller import InspectionController


class InspectorConsoleClient:
    """Minimal client that sends inspection data to the controller."""

    def __init__(self, controller: InspectionController) -> None:
        self.controller = controller

    def submit_inspection(self, request_data: dict) -> dict:
        return self.controller.inspect_device(request_data)


def main() -> None:
    # Assemble infrastructure objects
    repository = InMemoryInspectionRepository()
    payment_gateway = ConsolePaymentGateway()
    partner_gateway = ConsolePartnerGateway()

    # Compose services
    offer_service = OfferService(
        repository=repository,
        payment_gateway=payment_gateway,
        partner_gateway=partner_gateway,
    )
    inspection_service = InspectionService(
        repository=repository,
        offer_service=offer_service,
    )
    controller = InspectionController(inspection_service)
    client = InspectorConsoleClient(controller)

    # Simulate an inspection request from an inspector
    request_data = {
        "device_id": 1,
        "client_id": 42,
        "device_type_id": 3,
        "submitted_at": datetime.now(UTC),
        "inspector_id": 7,
        "condition": "good",
        "notes": "minor scratches",
    }

    response = client.submit_inspection(request_data)
    print("Inspection completed. Final offer:")
    for key, value in response.items():
        print(f"  {key}: {value}")


if __name__ == "__main__":
    main()
