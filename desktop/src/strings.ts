export const S = {
  title: "Connect to your Relay server",
  serverLabel: "Server address",
  urlPlaceholder: "https://relay.example.com",
  connect: "Continue",
  checking: "Checking server…",
  unreachable: "Couldn't reach a Relay server at that address.",
  invalidUrl: "That doesn't look like a valid address.",
  remembered: "Remembered servers",
  remove: "Remove",
} as const;

export const P = {
  title: "Preferences",
  servers: "Servers",
  add: "Add",
  launchAtLogin: "Launch Relay at login",
  switchTo: "Switch to",
} as const;
