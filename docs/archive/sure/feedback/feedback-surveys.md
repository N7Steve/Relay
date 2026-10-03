# Adding feature feedback surveys

See [Preview surveys and event capture](../hosting/preview-feedback.md) for
deployment behavior, privacy boundaries, and the first implementation's event
catalog and counting rules.

Use `feedback_config(:feature_name)` from `FeedbackHelper` to select a survey.
Project routing belongs in this helper and `config/initializers/posthog.rb`;
question wording, response mapping, UI, and events belong to the feature.

## Configuration

`self_hosted_feedback_project` reads the operator's public client token from
`POSTHOG_FEEDBACK_KEY` and ingestion host from `POSTHOG_FEEDBACK_HOST`.
`feedback_surveys` maps each feature to independent managed and self-hosted IDs.
Sankey uses `POSTHOG_SANKEY_SURVEY_ID` for managed installations and
`POSTHOG_SELF_HOSTED_SANKEY_SURVEY_ID` for self-hosting. No upstream destination
is bundled. Missing tokens or survey IDs return `{}` without a fallback.

Use `feedback_config(:sankey)` from the view. Self-hosted feedback also requires
production or the explicit development override and respects
`POSTHOG_FEEDBACK_ENABLED=false`. General analytics configuration is separate.
See the hosting guide for installation configuration and privacy boundaries.

## Adding the next feature

1. Create an API survey in each intended PostHog project. App and demo have
   distinct projects; self-hosted surveys belong in the operator-configured feedback project.
2. Add the feature to `feedback_surveys`, with a feature-specific environment
   variable for the managed survey and an explicit environment variable for
   self-hosting. Document the new environment variable in `.env.local.example`.
   Leave an unavailable destination unconfigured rather than borrowing an ID.
3. Call `feedback_config(:feature_name)` from the feature's view and pass values
   through escaped Stimulus data attributes. Keep the feature's access/preview
   gate at its existing web entry points; the helper does not grant access.
4. Implement the feature's survey contract and response mapping. Validate the
   active survey and question IDs, handle missing/blocked/opted-out analytics,
   and report success only after submission is accepted by the SDK.
5. Define the feature's event vocabulary and allowed properties. Preserve
   anonymous identity, existing capture opt-outs, and the self-hosted operator
   opt-out. Disable automatic capture, page tracking, session replay, and person
   profiles for the dedicated feedback client. Send free text only on explicit
   submission, and exclude financial records and incidental URL/device metadata.
6. Add offline tests for both destinations, distinct feature survey IDs, missing
   configuration, opt-outs, and the form's actual submission flow.

The helper only returns configuration; it does not initialize an SDK or submit
anything. The current `posthog.sankeyFeedback` client and its event allowlist are
Sankey-specific. Do not reuse its question assumptions or widen its event filter
implicitly when adding another feature. Make any shared browser-client extraction
alongside that feature with tests for both callers.

See `test/helpers/feedback_helper_test.rb` for routing coverage using a second
test-only feature. No placeholder surveys are registered in production.
