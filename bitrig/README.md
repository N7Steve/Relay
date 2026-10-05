# Relay for iOS and iPadOS

This SwiftUI client connects directly to a Relay instance with `X-Api-Key` authentication.

## Connecting

- Server: the URL of your self-hosted Relay instance.
- Create a **read/write** key under Settings → API keys, then paste it into the native app. The key is stored only in the device Keychain.

Do not commit an API key. There is no public demo server.

## Push notifications

The app target keeps the APNs entitlement and the `POST /api/v1/push_subscriptions` contract, but Relay is exclusively self-hosted and its server does not register, unregister or deliver push notifications. See [iOS push notifications in Relay](../docs/hosting/push-notifications.md). The project source intentionally keeps `aps-environment` set to `development`; Apple distribution signing replaces it with `production` for TestFlight and App Store builds.
