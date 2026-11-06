# Privacy and limits

The library has no I/O. The demo processes user-entered JSON in browser memory, uses text nodes/textarea values, and makes no data-upload, telemetry or account calls. It does not use localStorage, a service worker or a background save. A deliberate download is the user's own local export. Browser extensions and the browser's own behavior are outside this library's control.

Inspection notes, record IDs and field names can contain private information. Conflict keys contain IDs/keys and must not be sent as analytics identifiers. Review the final JSON before sharing. No anonymization, contact detection or content redaction is performed.

Only two branches against one baseline are modeled. There is no general version-control graph, timestamp precedence, fuzzy identity reconciliation, attachment merge or rich-text merge. Text values are whole fields: competing edits inside a long note require a source choice or manual correction of a source followed by a new comparison. There is no custom free-text conflict choice in this release.

The library validates collection/text bounds after receiving Elm values; it is not a JSON parser resource sandbox. The demo's 500,000-character input limit is a separate UI boundary. A production caller must apply its own byte, time and memory limits.
