# JSON boundary

```json
[
  {"id":"A101","fields":[
    {"key":"room","value":"Kitchen"},
    {"key":"note","value":"Synthetic observation"}
  ]}
]
```

`Property.ReviewMerge.Json.decoder` decodes and validates before constructing an opaque snapshot. Unknown JSON members are ignored; they are not copied into rows or output. Required strings/arrays must have the right type. Duplicate record IDs and duplicate field-list keys fail validation. Like normal Elm JSON decoders, duplicate object member names are not separately reported; use a canonical JSON producer if that matters to the caller.

Missing rows/fields express deletion relative to base. Empty string is an authored empty string, not deletion. An empty fields list is a real record with no fields; an empty snapshot is valid. Raw IDs allow ASCII letters, digits, dot, underscore and dash, 1–64 characters; no normalization is performed. Field keys are nonblank and at most 64 characters. Values are at most 2,000 characters.

The library's `validate` returns fixed issue codes with 1-based row numbers (0 for whole-snapshot issues), without copying source values into errors. The codec gives a fixed constraint message; a caller should not log the detailed JSON parser error object if source text is private. The demo shows only fixed parse/constraint messages and limits input size before decoding.

`encode` is a serializer, not a merge authorization. Application code should serialize only rows from a successful `finalize` when exporting a merge result. No conflict choices or source history are added automatically; store them separately if an audit trail is required.
