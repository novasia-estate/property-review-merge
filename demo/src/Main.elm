module Main exposing (main)

import Browser
import Dict exposing (Dict)
import File.Download
import Html exposing (Html, a, article, button, div, footer, h1, h2, h3, header, label, main_, nav, p, pre, section, span, text, textarea)
import Html.Attributes exposing (attribute, class, disabled, href, id, readonly, rows, value)
import Html.Events exposing (onClick, onInput)
import Json.Decode as D
import Json.Encode as E
import Property.ReviewMerge as M exposing (Choice(..), Conflict(..))
import Property.ReviewMerge.Json as Codec


type alias Model =
    { base : String, left : String, right : String, plan : Maybe M.Plan, choices : Dict String Choice, error : String, result : Maybe (List M.Row) }


type Msg
    = Edit String String
    | LoadExample
    | Compare
    | Select String Choice
    | Prepare
    | Download


main : Program () Model Msg
main =
    Browser.element { init = \_ -> ( compare example, Cmd.none ), update = update, view = view, subscriptions = \_ -> Sub.none }


record rid fields =
    { id = rid, fields = List.map (\( k, v ) -> { key = k, value = v }) fields }


example : Model
example =
    let
        encode rs = E.encode 2 (Codec.encode rs)
        base = [ record "A101" [ ( "room", "Kitchen" ), ( "note", "Handle needs review" ), ( "severity", "minor" ) ], record "A102" [ ( "room", "Bathroom" ), ( "status", "open" ) ] ]
        left = [ record "A101" [ ( "room", "Kitchen" ), ( "note", "Loose handle on upper cabinet" ), ( "severity", "minor" ) ] ]
        right = [ record "A101" [ ( "room", "Kitchen" ), ( "note", "Handle screw missing" ), ( "severity", "major" ) ], record "A102" [ ( "room", "Bathroom" ), ( "status", "assigned" ) ], record "A103" [ ( "room", "Balcony" ), ( "note", "Synthetic new observation" ) ] ]
    in
    { base = encode base, left = encode left, right = encode right, plan = Nothing, choices = Dict.empty, error = "", result = Nothing }


decode input =
    if String.length input > 500000 then
        Err "Input exceeds 500,000 characters."
    else
        D.decodeString Codec.decoder input |> Result.mapError (\_ -> "Invalid JSON or snapshot constraints.")


compare model =
    let
        result = Result.map3 M.merge (decode model.base) (decode model.left) (decode model.right)
    in
    case result of
        Ok plan -> { model | plan = Just plan, choices = Dict.empty, result = Nothing, error = "" }
        Err problem -> { model | plan = Nothing, choices = Dict.empty, result = Nothing, error = problem }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        LoadExample -> ( compare example, Cmd.none )
        Compare -> ( compare model, Cmd.none )
        Edit side input ->
            let
                cleared = { model | plan = Nothing, choices = Dict.empty, result = Nothing, error = "Inputs changed. Compare again before resolving or exporting." }
            in
            ( if side == "base" then { cleared | base = input } else if side == "left" then { cleared | left = input } else { cleared | right = input }, Cmd.none )

        Select key choice -> ( { model | choices = Dict.insert key choice model.choices, result = Nothing, error = "" }, Cmd.none )
        Prepare ->
            case model.plan of
                Nothing -> ( { model | error = "Compare valid snapshots first.", result = Nothing }, Cmd.none )
                Just plan ->
                    case M.finalize (Dict.toList model.choices) plan of
                        Ok result -> ( { model | result = Just result, error = "" }, Cmd.none )
                        Err _ -> ( { model | result = Nothing, error = "Resolve every conflict once. The combined result must remain within the snapshot limits." }, Cmd.none )

        Download ->
            case model.result of
                Nothing -> ( model, Cmd.none )
                Just result -> ( model, File.Download.string "merged-inspection-review.json" "application/json" (E.encode 2 (Codec.encode result)) )


pane side title content =
    label [ class "pane" ] [ span [] [ text title ], textarea [ value content, rows 12, onInput (Edit side), attribute "aria-label" title, attribute "spellcheck" "false" ] [] ]


showValue maybe =
    case maybe of
        Nothing -> "[absent / deleted]"
        Just value_ -> if value_ == "" then "[empty string]" else value_


showRow maybe =
    case maybe of
        Nothing -> "[record absent / deleted]"
        Just row -> E.encode 2 (Codec.encode [ row ])


conflictView selected conflict =
    let
        key = M.conflictKey conflict
        details =
            case conflict of
                FieldConflict c -> { title = c.recordId ++ " / " ++ c.field, base = showValue c.base, left = showValue c.left, right = showValue c.right }
                RecordConflict c -> { title = c.recordId ++ " / record conflict", base = showRow c.base, left = showRow c.left, right = showRow c.right }

        candidate caption choice content =
            div [ class "candidate" ]
                [ h3 [] [ text caption ], pre [] [ text content ]
                , button [ onClick (Select key choice), attribute "aria-pressed" (if Dict.get key selected == Just choice then "true" else "false") ] [ text ("Use " ++ caption) ]
                ]
    in
    article [ class "conflict" ]
        [ h2 [] [ text details.title ]
        , div [ class "candidates" ] [ candidate "base" KeepBase details.base, candidate "left" KeepLeft details.left, candidate "right" KeepRight details.right ]
        ]


view : Model -> Html Msg
view model =
    let
        pending = Maybe.map M.conflicts model.plan |> Maybe.withDefault []
        total = List.length pending
        selected = Dict.size model.choices
    in
    main_ []
        [ nav [] [ span [] [ text "OFFLINE INSPECTION / THREE-WAY REVIEW" ], a [ href "https://novasia.estate/" ] [ text "NovAsia Estate" ] ]
        , header [] [ h1 [] [ text "Property Review", Html.br [] [], text "Merge Desk." ], p [] [ text "Bring two inspection rounds together without losing a disagreement." ] ]
        , section [ class "notice" ] [ text "All loaded examples are synthetic. Work stays in this browser memory; no uploads or automatic saving. Matching uses exact record IDs and field keys. Review the final notes before sharing." ]
        , div [ class "actions" ] [ button [ onClick LoadExample ] [ text "Load synthetic example" ], button [ onClick Compare, class "primary" ] [ text "Compare snapshots" ] ]
        , div [ class "inputs" ] [ pane "base" "Base snapshot" model.base, pane "left" "Left inspection" model.left, pane "right" "Right inspection" model.right ]
        , div [ class "summary", attribute "role" "status" ] [ text (if model.plan == Nothing then "No current merge plan" else String.fromInt selected ++ " of " ++ String.fromInt total ++ " conflicts resolved") ]
        , p [ class "error", attribute "role" "alert" ] [ text model.error ]
        , div [] (List.map (conflictView model.choices) pending)
        , div [ class "actions" ] [ button [ onClick Prepare, disabled (model.plan == Nothing), class "primary" ] [ text "Prepare resolved JSON" ], button [ onClick Download, disabled (model.result == Nothing) ] [ text "Download merged JSON" ] ]
        , case model.result of
            Nothing -> p [] [ text "No partial export is available while conflicts remain unresolved." ]
            Just result -> section [ class "result" ] [ h2 [] [ text "Resolved inspection snapshot" ], p [] [ text (String.fromInt (List.length result) ++ " records. Original snapshots remain unchanged.") ], textarea [ readonly True, rows 12, value (E.encode 2 (Codec.encode result)), attribute "aria-label" "Resolved JSON" ] [] ]
        , footer [] [ text "Property Review Merge 1.0.0 · Pure Elm library + local desk · Developed by ", a [ href "https://novasia.estate/" ] [ text "NovAsia Estate" ], text ". Empty text differs from deletion. No automatic last-writer-wins or identity matching." ]
        ]
