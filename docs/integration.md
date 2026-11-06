# Integration workflow

Capture a common baseline before distributing offline copies. Assign stable inspection-record IDs at creation. Do not use this merger to reconcile unrelated snapshots or silently invented crosswalks.

Validate all three sources with `validate` or the JSON decoder. Build a merge plan and show every `Conflict` with all three source values. Distinguish a missing field, missing record and empty string. Collect explicit source choices keyed by `conflictKey`. Call `finalize`; handle `Err` without exporting provisional data. On success, show the final actual notes and require a human review before sharing or importing.

Any input edit invalidates choices and output. The bundled demo implements this lifecycle. A source choice can be revised before preparing the result, and finalizing one plan with different choice lists does not mutate the plan or sources.

If finalization reports `merged_snapshot_exceeds_limits`, split the source batch along stable record boundaries and reconcile again. Do not increase bounds or drop rows silently. A batch containing a record that exceeds the field/value bounds must be corrected before validation.

The package is pure Elm and needs only elm/core and elm/json. The demo is a separate Elm application using Browser, Html and File.Download. Its optimized JS is built from source in CI and can be hosted as ordinary static files. It is not an editor for legal, medical or financial records and does not approve the truth or severity of an inspection claim.
