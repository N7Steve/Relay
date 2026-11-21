import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="scheduled-payment-form"
export default class extends Controller {
  static targets = [
    "paymentType",
    "transferFields",
    "sharedExpenseFields",
    "frequency",
    "endDateFields",
    "amountEstimated",
    "autoConfirmFields",
  ];

  connect() {
    this.togglePaymentTypeFields();
    this.toggleFrequencyFields();
    this.toggleEstimatedAmountFields();
  }

  togglePaymentTypeFields() {
    if (!this.hasPaymentTypeTarget) return;

    const paymentType = this.paymentTypeTarget.value;
    if (this.hasTransferFieldsTarget) {
      this.transferFieldsTarget.classList.toggle(
        "hidden",
        paymentType !== "transfer",
      );
    }
    if (this.hasSharedExpenseFieldsTarget) {
      this.sharedExpenseFieldsTarget.classList.toggle(
        "hidden",
        paymentType !== "expense",
      );
    }
  }

  toggleFrequencyFields() {
    if (!this.hasFrequencyTarget || !this.hasEndDateFieldsTarget) return;

    const isOnce = this.frequencyTarget.value === "once";
    this.endDateFieldsTarget.classList.toggle("hidden", isOnce);
    this.endDateFieldsTarget.querySelectorAll("input").forEach((input) => {
      input.disabled = isOnce;
    });
  }

  toggleEstimatedAmountFields() {
    if (!this.hasAmountEstimatedTarget || !this.hasAutoConfirmFieldsTarget)
      return;

    const isEstimated = this.amountEstimatedTarget.checked;
    this.autoConfirmFieldsTarget.classList.toggle("hidden", isEstimated);
    const autoConfirmToggle = this.autoConfirmFieldsTarget.querySelector(
      "input[type=checkbox]",
    );
    if (isEstimated && autoConfirmToggle) autoConfirmToggle.checked = false;
  }
}
