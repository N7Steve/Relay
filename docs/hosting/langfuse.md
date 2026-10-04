# Remote LLM tracing removed

Relay removed Langfuse in pruning phase 3. Legacy `LANGFUSE_*` variables are
ignored. Use local Rails logs, DebugLogEntry and LlmUsage records for diagnostics.
