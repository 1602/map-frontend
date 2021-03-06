module Main exposing (Model, Msg(..), Touch(..), approx, bup, controls, decodeScreenPoint, distance, init, main, makeMask, mapImage, newCenter, ontouch, printCircle, printPath, printVisitedLocation, printVisitedSquares, renderVistedLocations, round, showMap, subscriptions, touchEventDecoder, update, view, zoomIncrement)

-- import Geolocation exposing (Error, Location)

import Browser
import Data.PathPoint exposing (PathPoint)
import Data.VisitedLocation exposing (VisitedLocation)
import Dict
import Html exposing (Html, button, div, h1, img, span, text)
import Html.Attributes exposing (class, src)
import Html.Events exposing (onClick)
import Http
import Json.Decode as Decode exposing (Decoder, Value, succeed)
import Request.Location
import Svg
import Svg.Attributes exposing (cx, cy, height, r, rx, ry, style, transform, viewBox, width, x, y)
import Svg.Events
import Task
import Time exposing (Posix)



---- MODEL ----


type alias Model =
    { error : Maybe String
    , watchLocation : Bool
    , lastLocation : Maybe PathPoint
    , visitedLocations : List VisitedLocation
    , squareSize : Float
    , ratio : Float
    , loading : Bool
    , touch : Maybe Touch
    , baseOffset : ( Float, Float )
    , verticalOffset : Float
    , horizontalOffset : Float
    , zoomLevel : Float
    , path : List PathPoint
    , time : Posix
    , selectedPath : Maybe Posix
    , mapOffset : ( Float, Float )
    , nextMapOffset : ( Float, Float )
    , mapUrl : String
    }


init : Value -> ( Model, Cmd Msg )
init _ =
    ( { error = Nothing
      , watchLocation = False
      , lastLocation = Nothing
      , visitedLocations = []
      , squareSize = 200
      , ratio = 1.7
      , loading = True
      , touch = Nothing
      , baseOffset = ( 0.0, 0.0 )
      , horizontalOffset = 0.0
      , verticalOffset = 0.0
      , zoomLevel = 9.9
      , path = []
      , time = Time.millisToPosix 0
      , selectedPath = Nothing
      , mapOffset = ( 0, 0 )
      , nextMapOffset = ( 0, 0 )
      , mapUrl = ""
      }
    , Cmd.batch
        [ Request.Location.list 8 Nothing
            |> Http.send VisitedLocations
        , Request.Location.path Nothing
            |> Http.send Path
        , Time.now
            |> Task.perform CurrentTime
        ]
    )



---- UPDATE ----


type Msg
    = NoOp
    | CurrentTime Posix
    | TouchStart Touch
    | TouchMove Touch
    | TouchEnd
    | ZoomIn
    | ZoomOut
    | SelectPath
    | VisitedLocations (Result Http.Error ( List VisitedLocation, ( PathPoint, Float, Float ) ))
    | Path (Result Http.Error (List PathPoint))
    | AdjustOffset


newCenter : Model -> Maybe ( Float, Float )
newCenter model =
    model.lastLocation
        |> Maybe.map
            (\loc ->
                ( loc.lat + model.verticalOffset
                , loc.long + model.horizontalOffset
                )
            )


distance : ( Float, Float ) -> ( Float, Float ) -> Float
distance ( a1, b1 ) ( a2, b2 ) =
    let
        da =
            a1 - a2 |> abs

        db =
            b1 - b2 |> abs
    in
    da * da + db * db |> sqrt


zoomIncrement : Float -> Float
zoomIncrement z =
    z / 10


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        CurrentTime t ->
            ( { model | time = t }, Cmd.none )

        AdjustOffset ->
            ( { model | mapOffset = model.nextMapOffset }, Cmd.none )

        Path res ->
            res
                |> Result.withDefault []
                |> (\pp -> ( { model | path = pp }, Cmd.none ))

        VisitedLocations res ->
            res
                |> Result.withDefault ( [], ( PathPoint 0 0 0, 200, 1.6 ) )
                |> (\( list, ( pp, ss, ratio ) ) ->
                        ( { model
                            | loading = False
                            , visitedLocations = list
                            , lastLocation = Just pp
                            , squareSize = ss
                            , ratio =
                                ratio

                            -- , nextMapOffset = ( model.verticalOffset, model.horizontalOffset )
                            , mapUrl =
                                {-
                                   "http://open.mapquestapi.com/staticmap/v5/map?key=ynpLd2go7xU9XrwAYFuhtQxubF83RFgA&size=580,580&type=light&zoom=13&center="
                                       ++ (toString <| pp.lat + model.verticalOffset * model.zoomLevel * 0.105)
                                       ++ ","
                                       ++ (toString <| pp.long + model.horizontalOffset * model.zoomLevel * 0.17)
                                -}
                                "https://maps.googleapis.com/maps/api/staticmap?center="
                                    ++ (String.fromFloat <| pp.lat)
                                    ++ ","
                                    ++ (String.fromFloat <| pp.long)
                                    ++ "&style=feature:road.local|element:geometry.fill|visibility:on|weight:2|color:white"
                                    ++ "&zoom=14&size=580x580&scale=2"
                                    ++ "&maptype=satellite"
                                    ++ "&geodesic=true"
                                    ++ "&key=AIzaSyCEImk9Kxih0sOYMDVu0QEZ7f5shXSWDaE"
                          }
                        , Cmd.none
                        )
                   )

        {-
           Move dir ->
               case model.location of
                   Just prevLocation ->
                       newLocation (move dir prevLocation) model

                   Nothing ->
                       model , Cmd.none)
        -}
        NoOp ->
            ( model, Cmd.none )

        {-
           RequestLocation ->
               { model | watchLocation = True } ! [ Geolocation.nowWith { enableHighAccuracy = False, timeout = Just 30000, maximumAge = Nothing } |> Task.attempt LocationUpdated ]
        -}
        {-
           LocationChanged l ->
               newLocation l model

           LocationUpdated res ->
               case res of
                   Ok l ->
                       newLocation l model

                   Err e ->
                       { model | error = Just e } , Cmd.none)
        -}
        ZoomIn ->
            ( { model | zoomLevel = model.zoomLevel - zoomIncrement model.zoomLevel }
            , Request.Location.list model.zoomLevel (newCenter model)
                |> Http.send VisitedLocations
            )

        ZoomOut ->
            ( { model | zoomLevel = model.zoomLevel + zoomIncrement model.zoomLevel }
            , Request.Location.list model.zoomLevel (newCenter model)
                |> Http.send VisitedLocations
            )

        SelectPath ->
            let
                selectedPath =
                    Just <|
                        case model.selectedPath of
                            Nothing ->
                                (model.time |> Time.posixToMillis) - 86400000

                            Just t ->
                                (t |> Time.posixToMillis) - 86400000
            in
            ( { model
                | selectedPath =
                    selectedPath |> Maybe.map Time.millisToPosix
              }
            , Request.Location.path (selectedPath |> Maybe.map toFloat)
                |> Http.send Path
            )

        TouchStart ts ->
            ( { model | touch = Just ts, baseOffset = ( model.horizontalOffset, model.verticalOffset ) }, Cmd.none )

        TouchEnd ->
            ( { model | touch = Nothing }
            , Request.Location.list model.zoomLevel (newCenter model)
                |> Http.send VisitedLocations
            )

        TouchMove touch ->
            case touch of
                ZoomTouch a b ->
                    let
                        currentDistance =
                            distance a b

                        initalDistance =
                            case model.touch of
                                Just (ZoomTouch a0 b0) ->
                                    distance a0 b0

                                _ ->
                                    currentDistance
                    in
                    if currentDistance < initalDistance && initalDistance - currentDistance > 25 then
                        ( { model | zoomLevel = model.zoomLevel + zoomIncrement model.zoomLevel, touch = Just touch }, Cmd.none )

                    else if currentDistance > initalDistance && initalDistance - currentDistance < -25 && model.zoomLevel > 2 then
                        ( { model | zoomLevel = model.zoomLevel - zoomIncrement model.zoomLevel, touch = Just touch }, Cmd.none )

                    else
                        ( model, Cmd.none )

                NavigateTouch ( x, y ) ->
                    let
                        tt =
                            model.touch |> Maybe.withDefault touch

                        ( baseHor, baseVer ) =
                            model.baseOffset

                        zoomCoefficient =
                            0.000013 * model.zoomLevel

                        ( deltaX, deltaY ) =
                            case tt of
                                NavigateTouch ( x0, y0 ) ->
                                    ( (x0 - x) * zoomCoefficient
                                    , (y0 - y) * zoomCoefficient
                                    )

                                _ ->
                                    ( 0.0, 0.0 )
                    in
                    ( { model
                        | touch = Just tt
                        , horizontalOffset = baseHor + deltaX
                        , verticalOffset = baseVer - deltaY
                      }
                    , Cmd.none
                    )



{-
   newLocation : Location -> Model -> ( Model, Cmd Msg )
   newLocation l model =
       { model | location = Just l, error = Nothing }
           ! [ case model.location of
                   Just prevLocation ->
                       if (approx prevLocation 0 0) /= (approx l 0 0) then
                           storeVisit l
                       else
                           Cmd.none

                   Nothing ->
                       storeVisit l
             ]
-}
{-
   storeVisit : Location -> Cmd Msg
   storeVisit loc =
       Request.Location.store loc.latitude loc.longitude
           |> Http.send (\_ -> NoOp)
-}
---- VIEW ----


bup : Float -> Float -> String
bup a step =
    let
        squareSize =
            2000
    in
    a
        * squareSize
        |> floor
        |> toFloat
        |> (+) step
        |> (\aa -> aa / squareSize)
        |> String.fromFloat


approx : PathPoint -> Float -> Float -> String
approx loc lat long =
    bup loc.lat lat ++ "," ++ bup loc.long long


controls : Html Msg
controls =
    div [ class "controls" ]
        [ span [ onClick ZoomIn, class "zoom" ] [ text "+" ]
        , span [ onClick ZoomOut, class "zoom" ] [ text "-" ]
        , span [ onClick SelectPath, class "zoom" ] [ text "<" ]
        ]


view : Model -> Html Msg
view model =
    if model.loading then
        span [] [ text "Loading..." ]

    else
        div
            [ Html.Attributes.style "width" "580px"
            , Html.Attributes.style "height" "580px"
            , Html.Attributes.style "overflow" "hidden"
            ]
            [ renderVistedLocations model
            , controls

            -- text "Location service is not available"
            -- , div [] [ model.touch |> toString |> text ]
            , case model.error of
                Just e ->
                    text e

                Nothing ->
                    text ""

            {-
               , div []
                   [ button [ onClick RequestLocation ] [ text "Locate me" ]
                   , button [ onClick (Move Up) ] [ text "Up" ]
                   , button [ onClick (Move Down) ] [ text "Down" ]
                   , button [ onClick (Move Left) ] [ text "Left" ]
                   , button [ onClick (Move Right) ] [ text "Right" ]
                   ]
            -}
            ]



{-
   horizontalOffset =
       -0.72


   verticalOffset =
       -0.02


-}


type Touch
    = NavigateTouch ( Float, Float )
    | ZoomTouch ( Float, Float ) ( Float, Float )


touchEventDecoder : Decoder Touch
touchEventDecoder =
    Decode.oneOf
        [ Decode.map2 ZoomTouch
            (decodeScreenPoint "0")
            (decodeScreenPoint "1")
        , Decode.map NavigateTouch
            (decodeScreenPoint "0")
        ]


decodeScreenPoint : String -> Decoder ( Float, Float )
decodeScreenPoint index =
    Decode.map2 (\x y -> ( x, y ))
        (Decode.at [ index, "screenX" ] Decode.float)
        (Decode.at [ index, "screenY" ] Decode.float)


ontouch : String -> Html.Attribute Msg
ontouch eventName =
    Html.Events.custom ("touch" ++ eventName)
        ((case eventName of
            "start" ->
                Decode.field "touches" touchEventDecoder |> Decode.map TouchStart

            "end" ->
                succeed TouchEnd

            _ ->
                Decode.field "touches" touchEventDecoder |> Decode.map TouchMove
         )
            |> Decode.map
                (\msg ->
                    { message = msg
                    , stopPropagation = True
                    , preventDefault = True
                    }
                )
        )


renderVistedLocations : Model -> Html Msg
renderVistedLocations model =
    let
        zoomLevel =
            model.zoomLevel

        horizontalOffset =
            model.horizontalOffset

        verticalOffset =
            model.verticalOffset

        visitedLocations =
            model.visitedLocations

        loc =
            model.lastLocation

        path =
            model.path

        squareSize =
            model.squareSize * 10
    in
    case loc of
        Nothing ->
            text ""

        Just location ->
            let
                centerA =
                    location.long

                centerB =
                    location.lat * model.ratio

                viewBoxA =
                    centerA * squareSize + (-5.1 * zoomLevel)

                viewBoxB =
                    centerB * squareSize + (5.1 * zoomLevel) |> negate

                viewBoxSize =
                    0.005 * squareSize * zoomLevel |> String.fromFloat
            in
            div
                [ ontouch "start"
                , ontouch "move"
                , ontouch "end"
                , Html.Attributes.style "width" "580px"
                , Html.Attributes.style "position" "relative"
                , Html.Attributes.style "height" "580px"
                ]
                [ Svg.svg
                    [ [ viewBoxA + horizontalOffset * squareSize |> String.fromFloat
                      , viewBoxB - verticalOffset * squareSize |> String.fromFloat
                      , viewBoxSize
                      , viewBoxSize
                      ]
                        |> String.join " "
                        |> viewBox

                    -- , transform "scale(1, -1)"
                    , style "background: #000000; height: 580px; width: 580px; opacity: 1; position: absolute; left: 0; top: 0"
                    ]
                    (List.concat
                        [ [ mapImage model.mapUrl model.mapOffset model.nextMapOffset squareSize viewBoxA viewBoxB viewBoxSize
                          ]
                        , visitedLocations
                            |> printVisitedSquares squareSize location
                        , [ visitedLocations
                                |> makeMask squareSize location
                          ]
                        , printPath path model.squareSize
                        , printCircle model.ratio location
                        ]
                    )

                --, showMap location model.squareSize ratio
                ]


mapImage : String -> ( Float, Float ) -> ( Float, Float ) -> Float -> Float -> Float -> String -> Svg.Svg Msg
mapImage mapUrl mapOffset nextMapOffset squareSize x y size =
    let
        ( verOff, horOff ) =
            mapOffset
    in
    Svg.image
        ([ Svg.Attributes.id "map"
         , Svg.Attributes.xlinkHref <| mapUrl
         , x + horOff * squareSize |> String.fromFloat |> Svg.Attributes.x
         , y + 2 - verOff * squareSize |> String.fromFloat |> Svg.Attributes.y
         , size |> Svg.Attributes.width
         , size |> Svg.Attributes.height
         , Svg.Attributes.style "mask: url(#mask)"
         ]
            ++ (if mapOffset /= nextMapOffset then
                    [ Svg.Events.on "load" (Decode.succeed AdjustOffset) ]

                else
                    []
               )
        )
        []



-- ++ "&maptype=hybrid"


printPath : List PathPoint -> Float -> List (Svg.Svg Msg)
printPath p squareSize =
    let
        path =
            p
                |> List.map
                    (\l ->
                        ( l.lat |> round (squareSize * 10) |> (*) (squareSize * -10)
                        , l.long |> round (squareSize * 10) |> (*) (squareSize * 10)
                        )
                    )
                |> List.foldl
                    (\coords list ->
                        case list of
                            [] ->
                                [ coords ]

                            head :: tail ->
                                if head == coords then
                                    list

                                else
                                    coords :: list
                    )
                    []
                |> List.reverse

        pathPoint movement ( lat, long ) =
            movement
                ++ String.fromFloat long
                ++ " "
                ++ String.fromFloat lat

        printDots =
            path
                |> List.map
                    (\( lat, long ) ->
                        Svg.circle
                            [ lat |> String.fromFloat |> cy
                            , long |> String.fromFloat |> cx
                            , r "0.13"
                            , Svg.Attributes.class "path-point"
                            ]
                            []
                    )
    in
    case path of
        [] ->
            [ Svg.path [] [] ]

        head :: tail ->
            Svg.path
                [ Svg.Attributes.d <|
                    pathPoint "M" head
                        ++ " "
                        ++ (tail |> List.map (pathPoint "L") |> String.join " ")
                , Svg.Attributes.fill "transparent"
                , Svg.Attributes.strokeWidth "0.05"
                , Svg.Attributes.class "path-line"

                --, Svg.Attributes.strokeOpacity "0.6"
                ]
                []
                :: printDots


round : Float -> Float -> Float
round squareSize a =
    a
        * squareSize
        |> floor
        |> toFloat
        |> (\aa -> aa / squareSize)


makeMask : Float -> PathPoint -> List VisitedLocation -> Svg.Svg Msg
makeMask squareSize location locations =
    let
        approximate ll =
            ll
                |> List.map
                    (\l ->
                        ( l.lat |> round (squareSize / 10)
                        , l.long |> round (squareSize / 10)
                        )
                    )
                |> List.foldl
                    (\coords ->
                        Dict.update coords
                            (\visits ->
                                case visits of
                                    Just n ->
                                        n + 1 |> Just

                                    Nothing ->
                                        1 |> Just
                            )
                    )
                    Dict.empty
                |> Dict.toList
                |> List.map (\( ( a, b ), c ) -> { lat = a, long = b, visits = c })
    in
    locations
        |> List.map
            (\vl ->
                let
                    squareId =
                        "cp" ++ String.fromInt vl.a ++ ":" ++ String.fromInt vl.b
                in
                [ Svg.rect
                    [ x "-0.5"
                    , y "-0.5"

                    --, rx "0.2"
                    --, ry "0.2"
                    , width "9.9"
                    , height "9.9"
                    , style
                        ("stroke-width:0.0;stroke-opacity:0.15;fill:#00FFFF;fill-opacity:"
                            ++ (if List.length vl.dots < 7 then
                                    "0.6"

                                else if List.length vl.dots < 30 then
                                    "0.7"

                                else
                                    "0.8"
                               )
                        )
                    ]
                    []
                ]
                    |> Svg.g
                        [ Svg.Attributes.transform <|
                            "translate("
                                ++ (toFloat vl.b |> (*) 10 |> String.fromFloat)
                                ++ ","
                                ++ (toFloat vl.a |> (*) 10 |> (+) 9.0 |> negate |> String.fromFloat)
                                ++ ")"
                        ]
            )
        |> Svg.mask [ Svg.Attributes.id "mask" ]


printVisitedSquares : Float -> PathPoint -> List VisitedLocation -> List (Svg.Svg Msg)
printVisitedSquares squareSize location locations =
    let
        approximate ll =
            ll
                |> List.map
                    (\l ->
                        ( l.lat |> round (squareSize / 10)
                        , l.long |> round (squareSize / 10)
                        )
                    )
                |> List.foldl
                    (\coords ->
                        Dict.update coords
                            (\visits ->
                                case visits of
                                    Just n ->
                                        n + 1 |> Just

                                    Nothing ->
                                        1 |> Just
                            )
                    )
                    Dict.empty
                |> Dict.toList
                |> List.map (\( ( a, b ), c ) -> { lat = a, long = b, visits = c })
    in
    locations
        |> List.map
            (\vl ->
                let
                    squareId =
                        "cp" ++ String.fromInt vl.a ++ ":" ++ String.fromInt vl.b
                in
                vl.dots
                    |> List.map
                        (\dot ->
                            Svg.circle
                                [ 9 - dot.a |> String.fromInt |> cy
                                , dot.b |> String.fromInt |> cx
                                , if dot.s == 3 then
                                    r "0.27"

                                  else if dot.s == 2 then
                                    r "0.2"

                                  else
                                    r "0.12"
                                , style <|
                                    --"fill:#99FFFF;"
                                    "fill:#ffeb3b;"
                                        ++ "fill-opacity:1"

                                {-
                                   ++ (if dot.s == 3 then
                                           "1"
                                       else if dot.s == 1 then
                                           "0.4"
                                       else
                                           "0.7"
                                      )
                                -}
                                ]
                                []
                        )
                    |> (::)
                        (Svg.rect
                            [ x "-0.5"
                            , y "-0.5"

                            --, rx "0.2"
                            --, ry "0.2"
                            , width "9.9"
                            , height "9.9"
                            , style
                                ("stroke-width:0.0;stroke-opacity:0.15;stroke:cyan;fill:#00FFFF;fill-opacity:"
                                    ++ (if List.length vl.dots < 7 then
                                            "0.1"

                                        else if List.length vl.dots < 30 then
                                            "0.2"

                                        else
                                            "0.3"
                                       )
                                )
                            ]
                            []
                        )
                    |> Svg.g
                        [ Svg.Attributes.transform <|
                            "translate("
                                ++ (vl.b |> (*) 10 |> String.fromInt)
                                ++ ","
                                ++ (vl.a |> (*) 10 |> (+) 9 |> negate |> String.fromInt)
                                ++ ")"
                        ]
            )


printCircle : Float -> PathPoint -> List (Svg.Svg Msg)
printCircle ratio location =
    let
        lat =
            location.lat * ratio * -2000

        long =
            location.long * 2000
    in
    [ Svg.circle
        [ lat |> String.fromFloat |> cy
        , long |> String.fromFloat |> cx
        , r "1.8"
        , style "fill:white;fill-opacity:0.3;"
        ]
        []
    , Svg.circle
        [ lat |> String.fromFloat |> cy
        , long |> String.fromFloat |> cx
        , r "0.7"
        , style "fill:white;fill-opacity:1;"
        ]
        []
    , Svg.circle
        [ lat |> String.fromFloat |> cy
        , long |> String.fromFloat |> cx
        , r "0.5"
        , style "fill:black;fill-opacity:1;"
        ]
        []
    ]


printVisitedLocation : Float -> Float -> Float -> Svg.Svg Msg
printVisitedLocation lat long visits =
    Svg.circle
        [ lat |> String.fromFloat |> cy
        , long |> String.fromFloat |> cx
        , if visits > 30 then
            r "0.00013"

          else if visits > 20 then
            r "0.00012"

          else if visits > 10 then
            r "0.00011"

          else
            r "0.0001"
        , style <|
            (if visits > 100 then
                "fill:#FFFF00;"

             else if visits > 50 then
                "fill:#FF0000;"

             else
                "fill:#99FFFF;"
            )
                ++ "fill-opacity:"
                ++ (if visits > 10 then
                        "1"

                    else if visits < 3 then
                        "0.4"

                    else
                        0.1 * visits |> String.fromFloat
                   )
        ]
        []



{-
   Svg.rect
       [ bup lat 0 |> y
       , bup long 0 |> x
       , width "0.0005"
       , height "0.0005"
       , style <|
           (if visits > 100 then
               "fill:#FFFF00;"
            else if visits > 50 then
               "fill:#FF0000;"
            else
               "fill:#00FF00;"
           )
               ++ "fill-opacity:"
               ++ (if visits > 10 then
                       "1"
                   else if visits < 3 then
                       "0.3"
                   else
                       0.1 * visits |> toString
                  )
       ]
       []
-}


showMap : PathPoint -> Float -> Float -> Html Msg
showMap location squareSize ratio =
    let
        lat =
            String.fromFloat location.lat

        long =
            String.fromFloat location.long

        long2 =
            String.fromFloat (location.long + 0.00001)

        a =
            approx location 0 0

        b =
            approx location 0 1

        c =
            approx location 1 1

        d =
            approx location 1 0
    in
    img
        [ src <|
            "https://maps.googleapis.com/maps/api/staticmap?center="
                ++ lat
                ++ ","
                ++ long
                ++ "&style=feature:road.local|element:geometry.fill|visibility:on|weight:2|color:black"
                -- ++ "&maptype=hybrid"
                ++ "&zoom=14&size=580x580&scale=2"
                ++ "&geodesic=true"
                ++ "&path="
                ++ "color:0x00000050|weight:1|fillcolor:0x00000033|geodesic:true|"
                ++ a
                ++ "|"
                ++ b
                ++ "|"
                ++ c
                ++ "|"
                ++ d
                ++ "|"
                ++ a
                ++ "&path=color:0x4285f4|weight:10|"
                ++ lat
                ++ ","
                ++ long
                ++ "|"
                ++ lat
                ++ ","
                ++ long2
                ++ "&key=AIzaSyCEImk9Kxih0sOYMDVu0QEZ7f5shXSWDaE"
        , Html.Attributes.width 580
        , Html.Attributes.height 580
        , Html.Attributes.style "top" "-22px"
        , Html.Attributes.style "left" "0"
        , Html.Attributes.style "position" "absolute"
        , Html.Attributes.style "opacity" "0.3"
        ]
        []


subscriptions : Model -> Sub Msg
subscriptions model =
    -- if model.watchLocation then
    -- Geolocation.changes LocationChanged
    -- else
    Time.every 60000 CurrentTime



---- PROGRAM ----


main : Program Value Model Msg
main =
    Browser.element
        { view = view
        , init = init
        , update = update
        , subscriptions = subscriptions
        }
