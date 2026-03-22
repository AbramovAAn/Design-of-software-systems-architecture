"""
Repository layer for storing and retrieving domain objects.

Following the **Dependency Inversion Principle** (part of SOLID),
services depend on these repository interfaces rather than concrete
implementations.  The simple in-memory implementation provided here
illustrates the **KISS** approach; it is sufficient for the lab without
introducing unnecessary complexity (avoiding violations of **YAGNI**).
"""
from __future__ import annotations
from typing import Dict

from .models import (
    InspectionResult,
    FinalOffer,
    Payment,
    PartnerTransfer,
)


class InspectionRepository:
    """Interface for persisting inspection results and final offers."""

    def next_inspection_result_id(self) -> int:
        raise NotImplementedError

    def next_final_offer_id(self) -> int:
        raise NotImplementedError

    def next_payment_id(self) -> int:
        raise NotImplementedError

    def next_partner_transfer_id(self) -> int:
        raise NotImplementedError

    def save_inspection_result(self, result: InspectionResult) -> None:
        raise NotImplementedError

    def save_final_offer(self, offer: FinalOffer) -> None:
        raise NotImplementedError

    def save_payment(self, payment: Payment) -> None:
        raise NotImplementedError

    def save_partner_transfer(self, transfer: PartnerTransfer) -> None:
        raise NotImplementedError


class InMemoryInspectionRepository(InspectionRepository):
    """A minimal in-memory repository for demonstration purposes."""

    def __init__(self) -> None:
        self.inspection_results: Dict[int, InspectionResult] = {}
        self.final_offers: Dict[int, FinalOffer] = {}
        self.payments: Dict[int, Payment] = {}
        self.transfers: Dict[int, PartnerTransfer] = {}

    def next_inspection_result_id(self) -> int:
        return len(self.inspection_results) + 1

    def next_final_offer_id(self) -> int:
        return len(self.final_offers) + 1

    def next_payment_id(self) -> int:
        return len(self.payments) + 1

    def next_partner_transfer_id(self) -> int:
        return len(self.transfers) + 1

    def save_inspection_result(self, result: InspectionResult) -> None:
        self.inspection_results[result.id] = result

    def save_final_offer(self, offer: FinalOffer) -> None:
        self.final_offers[offer.id] = offer

    def save_payment(self, payment: Payment) -> None:
        self.payments[payment.id] = payment

    def save_partner_transfer(self, transfer: PartnerTransfer) -> None:
        self.transfers[transfer.id] = transfer
