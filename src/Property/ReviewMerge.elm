module Property.ReviewMerge exposing
    ( Row, Field, Issue, Snapshot, Plan
    , Conflict(..), Choice(..)
    , validate, toRows, merge, conflicts, conflictKey, finalize
    )

{-| Three-way merge for independently edited offline property inspection notes.
No timestamps, last-writer-wins rule or automatic persistence are used.

# Input
@docs Row, Field, Issue, Snapshot, validate, toRows

# Merge and deliberate resolution
@docs Plan, Conflict, Choice, merge, conflicts, conflictKey, finalize
-}

import Dict exposing (Dict)
import Set


{-| One exact, case-sensitive field key and its unnormalized text value. -}
type alias Field =
    { key : String, value : String }


{-| A stable record ID with an explicitly authored list of fields. -}
type alias Row =
    { id : String, fields : List Field }


{-| Fixed validation code and 1-based row number; 0 means a snapshot-level issue. -}
type alias Issue =
    { row : Int, code : String }


type alias Fields =
    Dict String String


{-| Validated immutable snapshot. Construct it with `validate`. -}
type Snapshot
    = Snapshot (Dict String Fields)


{-| Opaque merge plan. Export is possible only through `finalize`. -}
type Plan
    = Plan (Dict String Fields) (List Conflict)


{-| A field conflict keeps absent values distinct from empty strings.
A record conflict represents a delete/edit conflict or different concurrent additions.
-}
type Conflict
    = FieldConflict { recordId : String, field : String, base : Maybe String, left : Maybe String, right : Maybe String }
    | RecordConflict { recordId : String, base : Maybe Row, left : Maybe Row, right : Maybe Row }


{-| Explicitly retain one of the three source values, including source deletion. -}
type Choice
    = KeepBase
    | KeepLeft
    | KeepRight


{-| Validate at most 200 rows, 30 fields/row, 64-character keys and 2,000-character values.
IDs are 1–64 ASCII letters/digits/dot/underscore/dash. Empty snapshots are valid.
Duplicate record IDs or field keys are rejected before constructing dictionaries.
-}
validate : List Row -> Result (List Issue) Snapshot
validate rows =
    let
        validId id =
            not (String.isEmpty id) && String.length id <= 64
                && String.all (\c -> String.contains (String.fromChar c) "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-") id

        issuesFor index row =
            List.filterMap identity
                [ if validId row.id then Nothing else Just { row = index + 1, code = "invalid_record_id" }
                , if List.length row.fields <= 30 then Nothing else Just { row = index + 1, code = "too_many_fields" }
                , if List.length row.fields == Set.size (Set.fromList (List.map .key row.fields)) then Nothing else Just { row = index + 1, code = "duplicate_field_key" }
                , if List.all (\f -> not (String.isEmpty (String.trim f.key)) && String.length f.key <= 64 && String.length f.value <= 2000) row.fields then Nothing else Just { row = index + 1, code = "invalid_field_key_or_value" }
                ]

        errors =
            (if List.length rows > 200 then [ { row = 0, code = "too_many_records" } ] else [])
                ++ (if List.length rows /= Set.size (Set.fromList (List.map .id rows)) then [ { row = 0, code = "duplicate_record_id" } ] else [])
                ++ List.concat (List.indexedMap issuesFor rows)
    in
    if List.isEmpty errors then
        Ok (Snapshot (Dict.fromList (List.map (\r -> ( r.id, Dict.fromList (List.map (\f -> ( f.key, f.value )) r.fields) )) rows)))
    else
        Err errors


asRow : String -> Fields -> Row
asRow id fields =
    { id = id, fields = List.map (\( key, value ) -> { key = key, value = value }) (Dict.toList fields) }


{-| Deterministic record/key order; values and Unicode remain unchanged. -}
toRows : Snapshot -> List Row
toRows (Snapshot records) =
    List.map (\( id, fields ) -> asRow id fields) (Dict.toList records)


keys3 : Dict String a -> Dict String a -> Dict String a -> List String
keys3 base left right =
    Set.toList (Set.fromList (Dict.keys base ++ Dict.keys left ++ Dict.keys right))


putMaybe : String -> Maybe a -> Dict String a -> Dict String a
putMaybe key value dict =
    case value of
        Just v -> Dict.insert key v dict
        Nothing -> Dict.remove key dict


sameRow : Maybe Fields -> Maybe Fields -> Bool
sameRow a b =
    Maybe.map Dict.toList a == Maybe.map Dict.toList b


{-| Compare base with two independently edited snapshots.
Identical edits and changes made by only one side merge automatically. Different
edits to one field, delete/edit pairs and different concurrent additions require choices.
-}
merge : Snapshot -> Snapshot -> Snapshot -> Plan
merge (Snapshot base) (Snapshot left) (Snapshot right) =
    let
        mergeOne id ( records, pending ) =
            let
                b = Dict.get id base
                l = Dict.get id left
                r = Dict.get id right
            in
            if sameRow l r then
                ( putMaybe id l records, pending )
            else if sameRow l b then
                ( putMaybe id r records, pending )
            else if sameRow r b then
                ( putMaybe id l records, pending )
            else
                case ( b, l, r ) of
                    ( Just bf, Just lf, Just rf ) ->
                        let
                            mergeField field ( fields, fieldConflicts ) =
                                let
                                    bv = Dict.get field bf
                                    lv = Dict.get field lf
                                    rv = Dict.get field rf
                                in
                                if lv == rv then
                                    ( putMaybe field lv fields, fieldConflicts )
                                else if lv == bv then
                                    ( putMaybe field rv fields, fieldConflicts )
                                else if rv == bv then
                                    ( putMaybe field lv fields, fieldConflicts )
                                else
                                    ( putMaybe field bv fields, FieldConflict { recordId = id, field = field, base = bv, left = lv, right = rv } :: fieldConflicts )

                            ( combined, more ) =
                                List.foldl mergeField ( Dict.empty, [] ) (keys3 bf lf rf)
                        in
                        ( Dict.insert id combined records, more ++ pending )

                    _ ->
                        ( records, RecordConflict { recordId = id, base = Maybe.map (asRow id) b, left = Maybe.map (asRow id) l, right = Maybe.map (asRow id) r } :: pending )

        ( automatic, outstanding ) =
            List.foldl mergeOne ( Dict.empty, [] ) (keys3 base left right)
    in
    Plan automatic (List.sortBy conflictKey outstanding)


{-| All unresolved source conflicts, in deterministic order. -}
conflicts : Plan -> List Conflict
conflicts (Plan _ pending) =
    pending


{-| Collision-free length-prefixed key for associating a choice with a conflict.
Keys include record IDs/field names and may be private; do not use them as telemetry.
-}
conflictKey : Conflict -> String
conflictKey conflict =
    let
        part s = String.fromInt (String.length s) ++ ":" ++ s
    in
    case conflict of
        RecordConflict c -> "record:" ++ part c.recordId
        FieldConflict c -> "field:" ++ part c.recordId ++ part c.field


pick : Choice -> a -> a -> a -> a
pick choice base left right =
    case choice of
        KeepBase -> base
        KeepLeft -> left
        KeepRight -> right


{-| Resolve every conflict exactly once. Unknown, duplicate and missing keys fail
the whole finalization. Source snapshots and the original plan remain immutable.
No partial result is returned while any conflict remains unresolved.
-}
finalize : List ( String, Choice ) -> Plan -> Result (List String) (List Row)
finalize choices (Plan automatic pending) =
    let
        selected = Dict.fromList choices
        expected = Set.fromList (List.map conflictKey pending)
        supplied = Set.fromList (List.map Tuple.first choices)
        errors =
            (if List.length choices /= Dict.size selected then [ "duplicate_choice_key" ] else [])
                ++ (if Set.isEmpty (Set.diff supplied expected) then [] else [ "unknown_choice_key" ])
                ++ (if Set.isEmpty (Set.diff expected supplied) then [] else [ "unresolved_conflicts" ])

        apply conflict records =
            case Dict.get (conflictKey conflict) selected of
                Nothing -> records
                Just choice ->
                    case conflict of
                        RecordConflict c ->
                            let
                                row = pick choice c.base c.left c.right
                                fields = Maybe.map (\r -> Dict.fromList (List.map (\f -> ( f.key, f.value )) r.fields)) row
                            in
                            putMaybe c.recordId fields records

                        FieldConflict c ->
                            Dict.update c.recordId (Maybe.map (putMaybe c.field (pick choice c.base c.left c.right))) records
    in
    if List.isEmpty errors then
        case validate (toRows (Snapshot (List.foldl apply automatic pending))) of
            Ok snapshot -> Ok (toRows snapshot)
            Err _ -> Err [ "merged_snapshot_exceeds_limits" ]
    else
        Err errors
