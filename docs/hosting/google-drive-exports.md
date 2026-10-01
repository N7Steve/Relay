# Automatic Google Drive exports

Sure can keep a transaction CSV in a user's personal Google Drive account. The
first run creates one file; later runs update that file by its Google Drive file
ID, so renaming or moving it does not change the link.

## Google Cloud configuration

1. Create or select a Google Cloud project and enable the Google Drive API.
2. Configure the OAuth consent screen.
3. Create an OAuth 2.0 Web application client.
4. Add this authorized redirect URI, using the public URL of the Sure instance:

   ```text
   https://sure.example.com/google_drive_connection/callback
   ```

5. In Sure, open **Settings → Exports**, expand **Google OAuth configuration**,
   and save that user's OAuth client ID and client secret. Each Sure user can
   use a different Google Cloud OAuth client.

As an installation-wide fallback, configure the application and worker
processes with:

   ```text
   GOOGLE_DRIVE_CLIENT_ID=...
   GOOGLE_DRIVE_CLIENT_SECRET=...
   ```

For Docker Compose deployments, store both values in the `.env` file beside the
Compose file and recreate both `web` and `worker`. The provided Compose examples
pass the variables through their shared Rails environment so they survive
restarts and image updates. A user's saved configuration takes precedence over
this fallback for their OAuth flow and scheduled jobs.

These credentials are intentionally separate from `GOOGLE_OAUTH_CLIENT_ID` and
`GOOGLE_OAUTH_CLIENT_SECRET`, which are used for signing in. Drive authorization
requests `openid`, `email`, and the narrow `drive.file` scope, plus offline access
so scheduled jobs can refresh access tokens.

Active Record Encryption must be configured in production. OAuth client IDs and
secrets, access tokens, refresh tokens, the Google subject, and the connected
email address are encrypted at rest when that application-wide encryption is
enabled. Saved client secrets are never rendered back into the form; leaving the
field empty preserves the existing value.

Changing a user's OAuth client ID or secret marks an existing Drive connection
for reauthorization because Google's refresh token belongs to the OAuth client
that issued it.

## Scheduling and files

`DispatchGoogleDriveExportsJob` runs every ten minutes and queues schedules whose
local run time is due. Sidekiq and Redis must be running for both the first export
and later scheduled exports.

Sure overwrites the generated CSV on every changed run. Users may rename or move
the file, but manual edits inside it will be replaced. Disconnecting Google Drive
or deleting a schedule leaves its existing Drive file untouched.

Schedules support three CSV formats:

- **Analytical** exports one row per logical transaction with a stable ID,
  explicit direction, positive amount, and optional category and tag columns.
- **Detailed** preserves the original entry-level transaction schema.
- **Account snapshot** exports the current selected account positions with a
  snapshot date, stable position ID, institution, normalized type and subtype,
  account scope (`included`, `tracking`, or `outside_finances`), absolute value,
  currency, and notes.

Analytical and snapshot files use UTF-8, comma-separated columns, decimal points,
and ISO dates. Snapshot schedules do not use transaction date ranges or category
and tag filters.

If the linked file is deleted, trashed, or loses write permission, Sure stops the
schedule instead of silently creating a new file with a different link. Reconnect
the account when Google reports an invalid or revoked refresh token.

Google Cloud projects with an external consent screen left in **Testing** can
issue short-lived refresh tokens. Publish the consent configuration before
relying on unattended long-term exports.
