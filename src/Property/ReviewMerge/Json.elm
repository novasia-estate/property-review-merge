module Property.ReviewMerge.Json exposing (decoder, encode)

{-| JSON boundary for note snapshots. Field lists preserve duplicate keys until
validation; they are not parsed as dictionaries that silently discard duplicates.

@docs decoder, encode
-}

import Json.Decode as D
import Json.Encode as E
import Property.ReviewMerge as Merge


{-| Decode a list of rows, then validate before creating an opaque snapshot.
Errors are fixed codes and row numbers rather than source values.
-}
decoder : D.Decoder Merge.Snapshot
decoder =
    D.list (D.map2 Merge.Row (D.field "id" D.string) (D.field "fields" (D.list (D.map2 Merge.Field (D.field "key" D.string) (D.field "value" D.string)))))
        |> D.andThen
            (\rows ->
                case Merge.validate rows of
                    Ok snapshot -> D.succeed snapshot
                    Err _ -> D.fail "Snapshot violates record, key, duplicate or size constraints."
            )


{-| Encode explicitly finalized rows; strings are escaped by Elm's JSON encoder.
Callers must obtain rows from `finalize` before treating them as a merge result.
-}
encode : List Merge.Row -> E.Value
encode rows =
    E.list
        (\row -> E.object
            [ ( "id", E.string row.id )
            , ( "fields", E.list (\f -> E.object [ ( "key", E.string f.key ), ( "value", E.string f.value ) ]) row.fields )
            ]
        )
        rows
