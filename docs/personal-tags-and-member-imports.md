# Personal tags and member imports

Members can import transaction CSVs (including Mint, Actual and YNAB formats)
and trade CSVs into accounts they own. All upload, mapping, row-edit and publish
steps resolve the actor's imports; queued publishing and reverting recheck account
ownership. Shared-account statement workflows retain their existing permissions.
Family backups, QIF account creation, account, category, merchant and rule imports
remain administrative operations.

Categories remain family-wide. Members may select existing categories when
classifying transactions or mapping CSV columns, but may not create, edit,
merge, bootstrap or delete them. This also applies through REST and MCP.

Tag catalogs and tag administration are personal, including for administrators.
Users can reuse the same tag name independently. A shared transaction still shows
all of its attached tags. Replacing a personal selection preserves tags belonging
to other users; another user's tag cannot be newly applied via a forged ID.

Migration 20261026190000 adds tag and import user references, an import actor
marker that keeps queued work denied after user deletion, and replaces the
family-wide tag-name index with a family/user/name index. Existing tags are
assigned to the family's earliest administrator (creation time, then ID), falling
back to its earliest member. Existing taggings are preserved. Historical imports
without an actor remain administrative, apart from account-scoped statements.
The migration is intentionally irreversible because personal names may overlap.
Deploy this migration through the normal deployment process before running the
new application. It has not been run on the user's database during development.

Complete backups preserve and remap tag owners and distinguish identical names
belonging to different users. Legacy interchange assigns tags to the importing
administrator, since it does not include portable member identities.
