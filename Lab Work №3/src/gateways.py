"""
Abstractions for external integrations.

Gateways encapsulate interactions with external services such as payment
providers and partner companies.  The use of interfaces here
demonstrates the **Interface Segregation** and **Dependency
Inversion** principles: high-level modules depend on abstractions rather
than concrete implementations.  Simple print statements suffice for the
lab (again honouring **KISS**), and no unnecessary functionality is
added (respecting **YAGNI**).
"""
from __future__ import annotations
from typing import Protocol


class PaymentGateway(Protocol):
    """Interface to initiate customer payments."""

    def pay(self, client_id: int, amount: float) -> None:
        """
        Initiate a payment to the client.

        :param client_id: Identifier of the client to pay.
        :param amount: Amount to pay.
        """
        ...


class PartnerGateway(Protocol):
    """Interface to transfer devices to a partner."""

    def transfer(self, submitted_device_id: int, partner_type: str) -> None:
        """
        Send the device to a partner for recycling or resale.

        :param submitted_device_id: ID of the device being sent.
        :param partner_type: Destination partner type (e.g. 'recycle', 'resell').
        """
        ...


class ConsolePaymentGateway:
    """A trivial payment gateway implementation that logs payments to console."""

    def pay(self, client_id: int, amount: float) -> None:
        # This simple implementation demonstrates KISS; in real systems this
        # would call an external payment API.
        print(f"[PaymentGateway] Paying client {client_id} amount {amount:.2f}")


class ConsolePartnerGateway:
    """A trivial partner gateway implementation that logs transfers to console."""

    def transfer(self, submitted_device_id: int, partner_type: str) -> None:
        print(
            f"[PartnerGateway] Transferring device {submitted_device_id} to partner for {partner_type}"
        )