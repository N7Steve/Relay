import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "fromAccount",
    "toAccount",
    "editableFields",
    "nativeFields",
    "name",
    "labels",
  ];
  static values = { accounts: Object, names: Object };

  connect() {
    this.refresh();
  }

  refresh() {
    const from = this.accountsValue[this.fromAccountTarget.value];
    const to = this.accountsValue[this.toAccountTarget.value];
    let operation = null;
    if (from && to) {
      if (from.managed && to.managed) operation = "transfer";
      else if (to.managed) operation = "contribution";
      else if (from.managed) operation = "withdrawal";
    }
    this.editableFieldsTarget.disabled = !!operation;
    this.editableFieldsTarget.hidden = !!operation;
    this.nativeFieldsTarget.hidden = !operation;
    if (!operation) return;

    const portfolio = operation === "withdrawal" ? from.name : to.name;
    this.nameTarget.textContent = this.namesValue[operation]
      .replaceAll("%{portfolio}", () => portfolio)
      .replaceAll("%{from}", () => from.name)
      .replaceAll("%{to}", () => to.name);
    for (const label of this.labelsTargets) {
      label.hidden = label.dataset.operation !== operation;
    }
  }
}
