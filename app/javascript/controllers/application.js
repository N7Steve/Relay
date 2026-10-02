import { Application } from "@hotwired/stimulus";

const application = Application.start();

// Configure Stimulus development experience
application.debug = false;
window.Stimulus = application;

Turbo.config.forms.confirm = (data) => {
  const confirmDialogController =
    application.getControllerForElementAndIdentifier(
      document.getElementById("confirm-dialog"),
      "confirm-dialog",
    );

  return confirmDialogController.handleConfirm(data);
};

const submittedDialogFrames = new WeakSet();

// A successful form response can navigate out of the dialog. Let that response
// clear its frame while continuing to protect forms during background refreshes.
document.addEventListener("turbo:before-fetch-response", (event) => {
  if (event.target.tagName !== "FORM") return;
  const frame = event.target.closest("turbo-frame");
  if (frame && event.detail.fetchResponse.succeeded) {
    submittedDialogFrames.add(frame);
  }
});

document.addEventListener("turbo:submit-start", (event) => {
  const frame = event.target.closest("turbo-frame");
  if (frame) submittedDialogFrames.delete(frame);
});

document.addEventListener("turbo:frame-load", (event) => {
  submittedDialogFrames.delete(event.target);
});

// Some pages still use a Turbo morph refresh after a background sync when they
// do not expose a narrower refresh frame. If the user has a transaction modal
// open, the server's HTML will have an empty `<turbo-frame id="drawer">`. Morphing would
// replace the user's open modal with this empty frame, abruptly closing it mid-edit.
// This listener stops the morphing of those frames if the user has them open but the server doesn't.
document.addEventListener("turbo:before-morph-element", (event) => {
  const target = event.target;
  const newElement = event.detail.newElement;

  if (
    target.tagName === "TURBO-FRAME" &&
    (target.id === "modal" || target.id === "drawer")
  ) {
    const currentHasContent = target.querySelector("dialog[open]") !== null;
    const newHasContent = newElement && newElement.innerHTML.trim() !== "";

    // If the modal is currently open but the server sends an empty frame,
    // preserve the user's open modal by skipping the morph for this element.
    if (
      currentHasContent &&
      !newHasContent &&
      !submittedDialogFrames.has(target)
    ) {
      event.preventDefault();
    }
  }
});

export { application };
