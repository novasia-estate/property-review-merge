module ReviewMergeTest exposing (tests)

import Expect
import Json.Decode as D
import Json.Encode as E
import Property.ReviewMerge as M exposing (Choice(..), Conflict(..))
import Property.ReviewMerge.Json as Codec
import Test exposing (Test, describe, test)


row id fields =
    { id = id, fields = List.map (\( k, v ) -> { key = k, value = v }) fields }


snapshot rows =
    -- Fixtures are validated, never constructed by exposing the opaque type.
    case M.validate rows of
        Ok s -> s
        Err _ -> snapshot []


plan b l r =
    M.merge (snapshot b) (snapshot l) (snapshot r)


finish b l r =
    M.finalize [] (plan b l r)


hasIssue code result =
    case result of
        Err issues -> Expect.equal True (List.any (\i -> i.code == code) issues)
        Ok _ -> Expect.fail "Expected validation error"


choose choice p =
    M.finalize (List.map (\c -> ( M.conflictKey c, choice )) (M.conflicts p)) p


tests : Test
tests =
    describe "Offline note merge contracts"
        [ test "empty snapshots" <| \_ -> Expect.equal (Ok []) (finish [] [] [])
        , test "unchanged record" <| \_ ->
            let
                r = row "a" [ ( "room", "Kitchen" ) ]
            in
            Expect.equal (Ok [ r ]) (finish [ r ] [ r ] [ r ])
        , test "left-only addition" <| \_ ->
            let
                r = row "a" []
            in
            Expect.equal (Ok [ r ]) (finish [] [ r ] [])
        , test "right-only addition" <| \_ ->
            let
                r = row "a" []
            in
            Expect.equal (Ok [ r ]) (finish [] [] [ r ])
        , test "same concurrent addition" <| \_ ->
            let
                r = row "a" []
            in
            Expect.equal (Ok [ r ]) (finish [] [ r ] [ r ])
        , test "different concurrent addition conflicts as record" <| \_ -> Expect.equal 1 (List.length (M.conflicts (plan [] [ row "a" [ ( "x", "L" ) ] ] [ row "a" [ ( "x", "R" ) ] ])))
        , test "left edit with unchanged right" <| \_ ->
            let
                b = row "a" [ ( "x", "B" ) ]
                l = row "a" [ ( "x", "L" ) ]
            in
            Expect.equal (Ok [ l ]) (finish [ b ] [ l ] [ b ])
        , test "right edit with unchanged left" <| \_ ->
            let
                b = row "a" [ ( "x", "B" ) ]
                r = row "a" [ ( "x", "R" ) ]
            in
            Expect.equal (Ok [ r ]) (finish [ b ] [ b ] [ r ])
        , test "same concurrent field edit" <| \_ ->
            let
                b = row "a" [ ( "x", "B" ) ]
                r = row "a" [ ( "x", "NEW" ) ]
            in
            Expect.equal (Ok [ r ]) (finish [ b ] [ r ] [ r ])
        , test "disjoint edits combine" <| \_ -> Expect.equal (Ok [ row "a" [ ( "x", "L" ), ( "y", "R" ) ] ]) (finish [ row "a" [ ( "x", "B" ), ( "y", "B" ) ] ] [ row "a" [ ( "x", "L" ), ( "y", "B" ) ] ] [ row "a" [ ( "x", "B" ), ( "y", "R" ) ] ])
        , test "left record deletion with unchanged right" <| \_ ->
            let
                r = row "a" []
            in
            Expect.equal (Ok []) (finish [ r ] [] [ r ])
        , test "both delete record" <| \_ -> Expect.equal (Ok []) (finish [ row "a" [] ] [] [])
        , test "delete versus edit cannot export" <| \_ -> Expect.equal (Err [ "unresolved_conflicts" ]) (finish [ row "a" [ ( "x", "B" ) ] ] [] [ row "a" [ ( "x", "R" ) ] ])
        , test "delete edit choose left removes record" <| \_ ->
            let
                p = plan [ row "a" [ ( "x", "B" ) ] ] [] [ row "a" [ ( "x", "R" ) ] ]
            in
            Expect.equal (Ok []) (choose KeepLeft p)
        , test "delete edit choose right retains edit" <| \_ ->
            let
                r = row "a" [ ( "x", "R" ) ]
                p = plan [ row "a" [ ( "x", "B" ) ] ] [] [ r ]
            in
            Expect.equal (Ok [ r ]) (choose KeepRight p)
        , test "delete edit choose base restores base" <| \_ ->
            let
                b = row "a" [ ( "x", "B" ) ]
                p = plan [ b ] [] [ row "a" [ ( "x", "R" ) ] ]
            in
            Expect.equal (Ok [ b ]) (choose KeepBase p)
        , test "field deletion is distinct from empty string" <| \_ ->
            let
                p = plan [ row "a" [ ( "x", "B" ) ] ] [ row "a" [] ] [ row "a" [ ( "x", "" ) ] ]
            in
            Expect.equal 1 (List.length (M.conflicts p))
        , test "field conflict choose left retains removal" <| \_ ->
            let
                p = plan [ row "a" [ ( "x", "B" ) ] ] [ row "a" [] ] [ row "a" [ ( "x", "R" ) ] ]
            in
            Expect.equal (Ok [ row "a" [] ]) (choose KeepLeft p)
        , test "field conflict choose right" <| \_ ->
            let
                p = plan [ row "a" [ ( "x", "B" ) ] ] [ row "a" [ ( "x", "L" ) ] ] [ row "a" [ ( "x", "R" ) ] ]
            in
            Expect.equal (Ok [ row "a" [ ( "x", "R" ) ] ]) (choose KeepRight p)
        , test "new field on one side" <| \_ -> Expect.equal (Ok [ row "a" [ ( "new", "L" ) ] ]) (finish [ row "a" [] ] [ row "a" [ ( "new", "L" ) ] ] [ row "a" [] ])
        , test "missing choices fail without partial output" <| \_ -> Expect.equal (Err [ "unresolved_conflicts" ]) (finish [] [ row "a" [ ( "x", "L" ) ] ] [ row "a" [ ( "x", "R" ) ] ])
        , test "unknown choice rejected" <| \_ -> Expect.equal (Err [ "unknown_choice_key" ]) (M.finalize [ ( "not-a-conflict", KeepLeft ) ] (plan [] [] []))
        , test "duplicate choices rejected" <| \_ ->
            let
                p = plan [] [ row "a" [] ] [ row "a" [ ( "x", "R" ) ] ]
                choices = List.map (\c -> ( M.conflictKey c, KeepLeft )) (M.conflicts p)
            in
            Expect.equal (Err [ "duplicate_choice_key" ]) (M.finalize (choices ++ choices) p)
        , test "record order deterministic" <| \_ -> Expect.equal (Ok [ row "a" [], row "z" [] ]) (finish [] [ row "z" [], row "a" [] ] [])
        , test "field order does not create conflict" <| \_ -> Expect.equal (Ok [ row "a" [ ( "x", "1" ), ( "y", "2" ) ] ]) (finish [] [ row "a" [ ( "y", "2" ), ( "x", "1" ) ] ] [ row "a" [ ( "x", "1" ), ( "y", "2" ) ] ])
        , test "unicode values exactly preserved" <| \_ ->
            let
                r = row "a" [ ( "описание", "ครัว / 厨房 / кухня" ) ]
            in
            Expect.equal (Ok [ r ]) (finish [] [ r ] [])
        , test "duplicate record IDs rejected" <| \_ -> hasIssue "duplicate_record_id" (M.validate [ row "a" [], row "a" [] ])
        , test "duplicate field keys rejected" <| \_ -> hasIssue "duplicate_field_key" (M.validate [ row "a" [ ( "x", "1" ), ( "x", "2" ) ] ])
        , test "invalid record ID rejected" <| \_ -> hasIssue "invalid_record_id" (M.validate [ row "a/b" [] ])
        , test "blank field key rejected" <| \_ -> hasIssue "invalid_field_key_or_value" (M.validate [ row "a" [ ( "  ", "x" ) ] ])
        , test "oversized value rejected" <| \_ -> hasIssue "invalid_field_key_or_value" (M.validate [ row "a" [ ( "x", String.repeat 2001 "a" ) ] ])
        , test "snapshot count bound" <| \_ -> hasIssue "too_many_records" (M.validate (List.map (\n -> row (String.fromInt n) []) (List.range 1 201)))
        , test "merged union bound rechecked" <| \_ ->
            let
                l = List.map (\n -> row ("L" ++ String.fromInt n) []) (List.range 1 150)
                r = List.map (\n -> row ("R" ++ String.fromInt n) []) (List.range 1 150)
            in
            Expect.equal (Err [ "merged_snapshot_exceeds_limits" ]) (finish [] l r)
        , test "JSON roundtrip" <| \_ ->
            let
                rows = [ row "a" [ ( "x", "</script>" ) ] ]
                encoded = E.encode 0 (Codec.encode rows)
            in
            Expect.equal (Ok rows) (Result.map M.toRows (D.decodeString Codec.decoder encoded))
        , test "JSON duplicate field entries rejected" <| \_ -> Expect.err (D.decodeString Codec.decoder "[{\"id\":\"a\",\"fields\":[{\"key\":\"x\",\"value\":\"1\"},{\"key\":\"x\",\"value\":\"2\"}]}]")
        , test "source plan is immutable across choices" <| \_ ->
            let
                p = plan [] [ row "a" [ ( "x", "L" ) ] ] [ row "a" [ ( "x", "R" ) ] ]
                first = choose KeepLeft p
                second = choose KeepRight p
            in
            Expect.notEqual first second
        ]
