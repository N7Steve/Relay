# iOS push notifications in Relay

Relay is exclusively self-hosted. The former SaaS APNs capability remains
unavailable: registration, unregistration, diagnostic controls and delivery are
disabled regardless of old mode flags or Apple credentials. Existing tokens
remain stored. Client authentication, API keys and OAuth continue to work.
The former configuration guide is archived at
[Sure hosted push](../archive/sure/hosting/push-notifications.md).

The transport code remains for the later client-scope decision; tests exercise
it with an explicit mock capability. There is no runtime switch to enable it.
