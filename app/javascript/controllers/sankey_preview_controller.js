import { Controller } from "@hotwired/stimulus";
import { compareSankeyData } from "utils/sankey_comparison";

export default class extends Controller {
  static targets = ["display", "expandButton", "expandedDialog"];
  static values = { legacyData: Object };

  connect() {
    this.state = "loading";
    this.comparisonResult = null;
    delete this.element.dataset.sankeyComparison;
  }

  disconnect() {
    this.clear();
  }

  clear() {
    this.comparisonResult = null;
    delete this.element.dataset.sankeyComparison;
    this.expandedDialogTarget.close();
    this.restoreDrag();
  }

  update({ detail }) {
    this.state = detail.state;
    this.comparisonResult = detail.graph
      ? compareSankeyData(this.legacyDataValue, detail.graph)
      : null;
    this.element.dataset.sankeyComparison = this.comparisonResult || "";
    this.expandButtonTarget.disabled = !detail.ready;
  }

  expand() {
    if (this.state !== "content" || this.expandedDialogTarget.open) return;
    this.section = this.element.closest(
      "[data-dashboard-sortable-target='section']",
    );
    this.originalDraggable = this.section?.getAttribute("draggable");
    this.section?.setAttribute("draggable", "false");
    this.expandedDialogTarget.showModal();
  }

  restoreDrag() {
    if (!this.section) return;
    if (this.originalDraggable === null)
      this.section.removeAttribute("draggable");
    else this.section.setAttribute("draggable", this.originalDraggable);
    this.section = null;
  }

  stopKeydown(event) {
    event.stopPropagation();
  }
}
