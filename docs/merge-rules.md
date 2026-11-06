# Merge rules

Record IDs and field keys are exact and case-sensitive. They must come from the same shared baseline; the software does not discover that two IDs refer to the same item.

For a value present in base/left/right:

1. Left equals right: retain that value or deletion.
2. Left equals base: retain right.
3. Right equals base: retain left.
4. Otherwise: require a choice.

If all three versions of a record exist, this rule is applied independently to fields. A one-sided field removal combines with an unchanged other side. A field removal versus a changed value is a conflict; `Nothing` differs from `Just ""`.

At record level, deleting an unchanged record is automatic, and both sides deleting it is automatic. Deleting a record while the other side edits it requires a whole-record choice. Different concurrent additions at the same ID also require a whole-record choice, even when their fields might look complementary; no baseline exists to justify combining them.

Conflict keys use a type prefix and length-prefixed record/field names. They are deterministic and collision-free for these types. A UI must associate exactly one choice with every current key. Never reuse choices after changing any input. `finalize` rejects duplicate, unknown and missing keys together and returns no partial result. It validates the merged union again before returning rows.

Output is sorted by record ID and field key. Values, Unicode and whitespace remain unchanged. Left/right are source labels, not priority, seniority or timestamps. This tool does not determine which inspector is correct.
