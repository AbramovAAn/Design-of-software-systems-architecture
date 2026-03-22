"""
Business service layer for the electronics recycling system.

These services orchestrate the use case of inspecting a device and
producing a final offer.  They are designed to be small, focused units
of behaviour, each with a single responsibility (**SRP**).  The
dependency on abstract repositories and gateways illustrates
**Dependency Inversion**.  Where behaviour is shared (e.g. price
calculation), helper methods are used to avoid duplication (**DRY**).
"""
from __future__ import annotations
from datetime import UTC, datetime

from .models import (
    InspectionResult,
    FinalOffer,
    Payment,
    PartnerTransfer,
    SubmittedDevice,
)
from .repositories import InspectionRepository
from .gateways import PaymentGateway, PartnerGateway


class InspectionService:
    """Service orchestrating the inspection process."""

    def __init__(
        self,
        repository: InspectionRepository,
        offer_service: "OfferService",
    ) -> None:
        self.repository = repository
        self.offer_service = offer_service

    def perform_inspection(
        self,
        submitted_device: SubmittedDevice,
        inspector_id: int,
        condition: str,
        notes: str,
    ) -> FinalOffer:
        """
        Inspect a device and return a final offer.

        This method encapsulates the high level flow: create an inspection
        result, persist it, then delegate to the offer service.  By
        delegating the pricing logic to OfferService the responsibilities
        remain separated (**SRP**).
        """
        # Create and persist the inspection result
        result = InspectionResult(
            id=self.repository.next_inspection_result_id(),
            submitted_device_id=submitted_device.id,
            inspector_id=inspector_id,
            condition=condition,
            notes=notes,
        )
        self.repository.save_inspection_result(result)

        # Delegate to offer service for pricing and further actions
        final_offer = self.offer_service.create_final_offer(
            submitted_device=submitted_device,
            inspection_result=result,
        )
        return final_offer


class OfferService:
    """Service responsible for computing the final offer and handling post-inspection actions."""

    def __init__(
        self,
        repository: InspectionRepository,
        payment_gateway: PaymentGateway,
        partner_gateway: PartnerGateway,
    ) -> None:
        self.repository = repository
        self.payment_gateway = payment_gateway
        self.partner_gateway = partner_gateway

    def create_final_offer(
        self,
        submitted_device: SubmittedDevice,
        inspection_result: InspectionResult,
    ) -> FinalOffer:
        """
        Determine the final offer based on inspection results and trigger
        follow-up actions.  This method demonstrates both **KISS** and
        **DRY**: the pricing logic is intentionally simple and kept in a
        helper method.  The final offer is saved via the repository and
        appropriate external calls are made via gateways.
        """
        # Compute the final price based on condition
        price = self._calculate_price(inspection_result.condition)
        decision = "recycle" if inspection_result.condition.lower() == "broken" else "resell"

        offer = FinalOffer(
            id=self.repository.next_final_offer_id(),
            submitted_device_id=inspection_result.submitted_device_id,
            final_price=price,
            decision=decision,
        )
        self.repository.save_final_offer(offer)

        # Initiate payment if there is a positive price
        if price > 0:
            payment = Payment(
                id=self.repository.next_payment_id(),
                final_offer_id=offer.id,
                amount=price,
                payment_date=datetime.now(UTC),
                status="paid",
            )
            self.repository.save_payment(payment)
            # Use the payment gateway; high-level code depends on abstraction
            self.payment_gateway.pay(
                client_id=submitted_device.client_id,
                amount=price,
            )

        # Always transfer the device either for resale or recycling
        transfer = PartnerTransfer(
            id=self.repository.next_partner_transfer_id(),
            final_offer_id=offer.id,
            partner_type=decision,
            transfer_date=datetime.now(UTC),
            status="sent",
        )
        self.repository.save_partner_transfer(transfer)
        self.partner_gateway.transfer(
            submitted_device_id=inspection_result.submitted_device_id,
            partner_type=decision,
        )
        return offer

    def _calculate_price(self, condition: str) -> float:
        """
        Compute a price based on the device condition.

        This private helper method avoids duplicating the pricing logic
        (**DRY**) and keeps the pricing rules in one place.  In future
        iterations a more sophisticated algorithm could be introduced
        without modifying callers (**Open/Closed Principle**).
        """
        condition = condition.lower()
        if condition == "new":
            return 100.0
        if condition == "good":
            return 70.0
        if condition == "fair":
            return 40.0
        if condition == "broken":
            return 0.0
        # Default fallback price
        return 10.0
