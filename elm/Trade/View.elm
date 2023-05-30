module Trade.View exposing (root)

import Array
import BigInt exposing (BigInt)
import Collage exposing (Collage)
import Collage.Render
import CommonTypes exposing (..)
import Config
import Contracts.Types as CTypes exposing (FullTradeInfo)
import Currencies exposing (Price)
import DateFormat
import Element exposing (Attribute, Element)
import Element.Background
import Element.Border
import Element.Events
import Element.Font
import Element.Input
import Eth.Net
import Eth.Types exposing (Address)
import Eth.Utils
import Helpers.Element as EH
import Helpers.Eth as EthHelpers
import Helpers.Time as TimeHelpers
import Images exposing (Image)
import Markdown
import PaymentMethods exposing (PaymentMethod)
import Time
import TokenValue exposing (TokenValue)
import Trade.ChatHistory.View as ChatHistory
import Trade.Types exposing (..)
import TradeCache.Types exposing (TradeCache)
import Wallet


root : DisplayProfile -> Time.Posix -> List TradeCache -> Model -> ( Element Msg, List (Element Msg) )
root dProfile time tradeCaches model =
    ( EH.submodelContainer
        1800
        dProfile
        Nothing
        (Just <|
            Element.row
                [ Element.width Element.fill ]
                [ let
                    addrStr =
                        case CTypes.getCreationInfo model.trade of
                            Just creationInfo ->
                                Eth.Utils.addressToString creationInfo.address

                            _ ->
                                "..."
                  in
                  case dProfile of
                    Desktop ->
                        Element.el
                            [ Element.centerX
                            , Element.Font.size 18
                            ]
                        <|
                            Element.text <|
                                "Trade at "
                                    ++ addrStr

                    Mobile ->
                        Element.column
                            [ Element.centerX
                            , Element.Font.size 12
                            , Element.padding 4
                            ]
                            [ Element.el [ Element.centerX ] <| Element.text "Trade at"
                            , Element.el [ Element.centerX ] <| Element.text addrStr
                            ]
                , case model.trade of
                    CTypes.LoadedTrade trade ->
                        Element.el
                            [ Element.below <|
                                if model.showOptions then
                                    EH.modal
                                        (Element.rgba 0 0 0 0.1)
                                        False
                                        NoOp
                                        (ToggleShowOptions False)
                                        (optionsMenu trade)

                                else
                                    Element.none
                            , Element.alignRight
                            , Element.centerY
                            ]
                            (Element.el
                                [ Element.paddingXY 5 5
                                , Element.centerY
                                , Element.pointer
                                , EH.onClickNoPropagation (ToggleShowOptions True)
                                ]
                             <|
                                EH.optionsDots dProfile
                            )

                    _ ->
                        Element.none
                ]
        )
        (Element.el
            [ Element.padding (30 |> changeForMobile 10 dProfile)
            , Element.width Element.fill
            ]
            (case model.trade of
                CTypes.LoadedTrade tradeInfo ->
                    Element.column
                        [ Element.width Element.fill
                        , Element.height Element.fill
                        , Element.spacing 40
                        ]
                        [ header time dProfile tradeInfo model.wallet tradeCaches model.showStatsModal
                        , Element.el
                            [ Element.width Element.fill
                            , Element.paddingXY 40 0 |> changeForMobile (Element.paddingXY 10 0) dProfile
                            , Element.spacing 40
                            ]
                            (phasesElement dProfile tradeInfo model.expandedPhase model.wallet time)
                        ]

                CTypes.PartiallyLoadedTrade partialTradeInfo ->
                    Element.el
                        [ Element.centerX
                        , Element.centerY
                        , Element.Font.size (30 |> changeForMobile 20 dProfile)
                        ]
                        (Element.text "Loading trade info...")

                CTypes.Invalid ->
                    Element.el
                        [ Element.centerX
                        , Element.centerY
                        , Element.Font.size (30 |> changeForMobile 20 dProfile)
                        ]
                        (Element.text "Invalid trade")
            )
        )
    , [ chatOverlayElement dProfile model
      , getTxModalOrNone dProfile model
      ]
    )


optionsMenu : CTypes.FullTradeInfo -> Element Msg
optionsMenu trade =
    EH.basicOpenDropdown
        [ Element.moveDown 5
        , Element.alignRight
        , EH.moveToFront
        ]
        Nothing
        [ ( Element.text "Duplicate"
          , DuplicateClicked trade.reference
          )
        ]


header : Time.Posix -> DisplayProfile -> FullTradeInfo -> Wallet.State -> List TradeCache -> Bool -> Element Msg
header currentTime dProfile trade wallet tradeCaches showStatsModal =
    case dProfile of
        Desktop ->
            Element.row
                [ Element.width Element.fill
                , Element.spaceEvenly
                ]
                [ tradeStatusElement trade
                , daiAmountElement trade wallet
                , fiatElement trade
                , statsElement dProfile trade tradeCaches showStatsModal
                ]

        Mobile ->
            Element.row
                [ Element.width Element.fill
                ]
                [ Element.el [ Element.alignLeft, Element.alignTop ] <|
                    offerElement trade
                , Element.el [ Element.alignRight, Element.alignTop ] <|
                    statsElement dProfile trade tradeCaches showStatsModal
                ]


tradeStatusElement : FullTradeInfo -> Element Msg
tradeStatusElement trade =
    EH.withHeader
        "Trade Status"
        (Element.column
            [ Element.Font.size 24
            , Element.Font.medium
            , Element.spacing 8
            ]
            [ Element.text
                (case trade.state.phase of
                    CTypes.Open ->
                        case trade.parameters.initiatorRole of
                            Buyer ->
                                "Open Buy Offer"

                            Seller ->
                                "Open Sell Offer"

                    CTypes.Committed ->
                        "Committed"

                    CTypes.Judgment ->
                        "Judgment"

                    CTypes.Closed ->
                        "Closed"
                )
            , EH.etherscanAddressLink
                [ Element.Font.size 12
                , Element.Font.color EH.blue
                , Element.Font.underline
                ]
                trade.reference.factory
                trade.creationInfo.address
            ]
        )


offerElement : FullTradeInfo -> Element Msg
offerElement trade =
    let
        preDaiText =
            case trade.parameters.initiatorRole of
                Buyer ->
                    "Buying"

                Seller ->
                    "Selling"
    in
    Element.column
        [ Element.spacing 5
        , Element.alignTop
        ]
        [ Element.el
            [ Element.Font.size 18
            , Element.Font.bold
            , Element.centerX
            ]
            (Element.text "Offer")
        , Element.row
            [ Element.spacing 7
            , Element.Font.size 16
            ]
            [ Element.column
                [ Element.spacing 5
                ]
                [ Element.el [ Element.alignRight ] <|
                    Element.text preDaiText
                , Element.el [ Element.alignRight ] <|
                    Element.text "for"
                ]
            , Element.column
                [ Element.spacing 5 ]
                [ Element.el [ Element.alignLeft ] <|
                    Element.text <|
                        TokenValue.toConciseString trade.parameters.tradeAmount
                            ++ " "
                            ++ tokenUnitName trade.reference.factory
                , Element.el [ Element.alignLeft ] <|
                    Element.text <|
                        Currencies.toString trade.terms.price
                ]
            ]
        ]


daiAmountElement : FullTradeInfo -> Wallet.State -> Element Msg
daiAmountElement trade wallet =
    let
        maybeInitiatorOrResponder =
            Wallet.userInfo wallet
                |> Maybe.map .address
                |> Maybe.andThen (CTypes.getInitiatorOrResponder trade)
    in
    EH.withHeader
        (case ( trade.parameters.initiatorRole, maybeInitiatorOrResponder ) of
            ( Buyer, Just Initiator ) ->
                "You're Buying"

            ( Buyer, _ ) ->
                "Buying"

            ( Seller, Just Initiator ) ->
                "You're Selling"

            ( Seller, _ ) ->
                "Selling"
        )
        (renderDaiAmount trade.parameters.tradeAmount)


renderDaiAmount : TokenValue -> Element Msg
renderDaiAmount daiAmount =
    Element.row
        [ Element.spacing 8 ]
        [ Images.toElement [] Images.daiSymbol
        , Element.el
            [ Element.Font.size 24
            , Element.Font.medium
            ]
            (Element.text <| TokenValue.toConciseString daiAmount)
        ]


fiatElement : FullTradeInfo -> Element Msg
fiatElement trade =
    EH.withHeader
        "For"
        (renderPrice trade.terms.price)


renderPrice : Price -> Element Msg
renderPrice price =
    Element.row
        [ Element.spacing 5 ]
        [ Currencies.icon price.symbol
            |> Maybe.withDefault Element.none
        , Element.el
            [ Element.Font.size 24
            , Element.Font.medium
            ]
            (Element.text <| Currencies.toString price)
        ]


type alias Stats =
    { asRole : BuyerOrSeller
    , firstTrade : Maybe Time.Posix
    , numTrades : Int
    , numBurns : Int
    , numReleases : Int
    , numAborts : Int
    , amountBurned : TokenValue
    , amountReleased : TokenValue
    }


generateUserStats : List TradeCache -> BuyerOrSeller -> Address -> Stats
generateUserStats tradeCaches forRole userAddress =
    let
        fullTradesByUserAsRole =
            tradeCaches
                |> List.map
                    (\tradeCache ->
                        tradeCache.trades
                            |> Array.toList
                            |> List.filterMap
                                (\t ->
                                    case t of
                                        CTypes.LoadedTrade loadedT ->
                                            Just loadedT

                                        _ ->
                                            Nothing
                                )
                            |> List.filter
                                -- filter for trades that share the same user in the same role
                                (\t ->
                                    CTypes.getBuyerOrSeller t userAddress == Just forRole
                                )
                    )
                |> List.concat

        talliedVals =
            fullTradesByUserAsRole
                |> List.foldl
                    (\trade tallied ->
                        case trade.state.closedReason of
                            CTypes.Released ->
                                { tallied
                                    | numReleases = tallied.numReleases + 1
                                    , amountReleased =
                                        TokenValue.add
                                            tallied.amountReleased
                                            trade.parameters.tradeAmount
                                }

                            CTypes.Burned ->
                                { tallied
                                    | numBurns = tallied.numBurns + 1
                                    , amountBurned =
                                        TokenValue.add
                                            tallied.amountBurned
                                            trade.parameters.tradeAmount
                                }

                            CTypes.Aborted ->
                                { tallied | numAborts = tallied.numAborts + 1 }

                            _ ->
                                tallied
                    )
                    { numBurns = 0
                    , numReleases = 0
                    , numAborts = 0
                    , amountBurned = TokenValue.zero
                    , amountReleased = TokenValue.zero
                    }

        numTrades =
            List.length fullTradesByUserAsRole

        firstTradeDate =
            fullTradesByUserAsRole
                |> List.filterMap
                    (\t ->
                        Time.posixToMillis t.phaseStartInfo.committedTime
                            |> (\millis ->
                                    if millis == 0 then
                                        Nothing

                                    else
                                        Just millis
                               )
                    )
                |> List.sort
                |> List.head
                |> Maybe.map Time.millisToPosix
    in
    { asRole = forRole
    , numTrades = numTrades
    , firstTrade = firstTradeDate
    , numBurns = talliedVals.numBurns
    , numReleases = talliedVals.numReleases
    , numAborts = talliedVals.numAborts
    , amountBurned = talliedVals.amountBurned
    , amountReleased = talliedVals.amountReleased
    }


statsElement : DisplayProfile -> FullTradeInfo -> List TradeCache -> Bool -> Element Msg
statsElement dProfile trade tradeCaches showModal =
    let
        userStats =
            trade.parameters.initiatorAddress
                |> generateUserStats tradeCaches trade.parameters.initiatorRole

        headerText =
            buyerOrSellerToString trade.parameters.initiatorRole
                ++ " Stats"

        statsEl =
            let
                ( fontSize, imageHeight ) =
                    case dProfile of
                        Desktop ->
                            ( 24, 28 )

                        Mobile ->
                            ( 18, 22 )
            in
            Element.row
                [ Element.width Element.fill
                , Element.spacing (20 |> changeForMobile 10 dProfile)
                , Element.padding (0 |> changeForMobile 7 dProfile)
                , Element.pointer
                , EH.onClickNoPropagation ToggleStatsModal
                , Element.Font.size fontSize
                ]
                (List.map
                    (Element.row [ Element.spacing 5 ])
                    [ [ Images.toElement
                            [ Element.height <| Element.px imageHeight
                            ]
                            Images.released
                      , Element.el
                            [ Element.Font.medium
                            , Element.Font.color <| EH.releasedIconColor
                            ]
                            (Element.text (String.padLeft 2 '0' <| String.fromInt userStats.numReleases))
                      ]
                    , [ Images.toElement
                            [ Element.height <| Element.px imageHeight
                            ]
                            Images.aborted
                      , Element.el
                            [ Element.Font.medium
                            , Element.Font.color <| EH.abortedIconColor
                            ]
                            (Element.text (String.padLeft 2 '0' <| String.fromInt userStats.numAborts))
                      ]
                    , [ Images.toElement
                            [ Element.height <| Element.px imageHeight
                            ]
                            Images.burned
                      , Element.el
                            [ Element.Font.medium
                            , Element.Font.color <| EH.softRed
                            ]
                            (Element.text (String.padLeft 2 '0' <| String.fromInt userStats.numBurns))
                      ]
                    ]
                )
    in
    Element.el
        ([ Element.alignTop ]
            ++ (if showModal then
                    [ Element.below
                        (Element.el
                            [ Element.moveDown (30 |> changeForMobile 10 dProfile)
                            , Element.alignRight
                            ]
                            (statsModal dProfile trade.reference.factory trade.parameters.initiatorAddress userStats)
                        )
                    ]

                else
                    []
               )
        )
        (case dProfile of
            Desktop ->
                EH.withHeader
                    headerText
                    statsEl

            Mobile ->
                Element.column
                    [ Element.spacing 5
                    , Element.alignTop
                    ]
                    [ Element.el
                        [ Element.Font.size 18
                        , Element.Font.bold
                        , Element.centerX
                        , Element.alignTop
                        ]
                        (Element.text headerText)
                    , statsEl
                    ]
        )


statsModal : DisplayProfile -> FactoryType -> Address -> Stats -> Element Msg
statsModal dProfile factoryType address stats =
    let
        statEl titleString statString =
            Element.column
                [ Element.Font.size (18 |> changeForMobile 14 dProfile)
                , Element.spacing (6 |> changeForMobile 3 dProfile)
                ]
                [ Element.el
                    [ Element.Font.bold ]
                    (Element.text titleString)
                , Element.el
                    [ Element.Font.regular ]
                    (Element.text statString)
                ]

        statsBody =
            Element.column
                [ Element.spacing (23 |> changeForMobile 16 dProfile)
                , Element.width Element.fill
                ]
                (List.map
                    (\( titleString, statString ) -> statEl titleString statString)
                    [ ( "First Trade"
                      , case stats.firstTrade of
                            Just date ->
                                dateFormatter
                                    Time.utc
                                    date

                            Nothing ->
                                "No Committed Trades yet!"
                      )
                    , ( "Release Outcomes"
                      , String.fromInt stats.numReleases
                            ++ " trades / "
                            ++ TokenValue.toConciseString stats.amountReleased
                            ++ " "
                            ++ tokenUnitName factoryType
                            ++ " Released"
                      )
                    , ( "Abort Outcomes"
                      , String.fromInt stats.numAborts
                            ++ " trades"
                      )
                    , ( "Burn Outcomes"
                      , String.fromInt stats.numBurns
                            ++ " trades / "
                            ++ TokenValue.toConciseString stats.amountBurned
                            ++ " "
                            ++ tokenUnitName factoryType
                            ++ " Burned"
                      )
                    ]
                    ++ [ Element.el [ Element.centerX ]
                            (EH.blueButton dProfile [] [ "View User History" ] (ViewUserHistory stats.asRole))
                       ]
                )

        dateFormatter =
            DateFormat.format
                [ DateFormat.monthNameFull
                , DateFormat.text ", "
                , DateFormat.yearNumber
                ]
    in
    Element.column
        [ Element.Border.rounded 8
        , Element.clipX
        , Element.clipY
        , Element.Background.color EH.lightGray
        , Element.spacing 1
        , Element.Border.shadow
            { offset = ( 0, 0 )
            , size = 0
            , blur = 20
            , color = Element.rgba 0 0 0 0.08
            }
        ]
        [ Element.el
            [ Element.width Element.fill
            , Element.Background.color EH.white
            , Element.padding (17 |> changeForMobile 10 dProfile)
            ]
            (EH.ethAddress (18 |> changeForMobile 14 dProfile) address)
        , Element.el
            [ Element.width Element.fill
            , Element.Background.color EH.white
            , Element.padding 17
            ]
            statsBody
        ]


phasesElement : DisplayProfile -> FullTradeInfo -> CTypes.Phase -> Wallet.State -> Time.Posix -> Element Msg
phasesElement dProfile trade expandedPhase wallet currentTime =
    case trade.state.phase of
        CTypes.Closed ->
            Element.row
                [ Element.centerX
                , Element.Border.rounded 12
                , Element.spacing 10
                , Element.padding 10
                , Element.Background.color EH.activePhaseBackgroundColor
                , Element.Font.size 24
                , Element.Font.semiBold
                , Element.Font.color EH.white
                ]
                [ Element.text <| "Trade " ++ closedReasonToText trade.state.closedReason
                , chatHistoryButton
                ]

        _ ->
            case dProfile of
                Desktop ->
                    Element.column
                        [ Element.width Element.fill
                        , Element.spacing 10
                        ]
                        [ Element.row
                            [ Element.width Element.fill
                            , Element.height Element.shrink
                            , Element.spacing 20
                            ]
                            [ phaseElement dProfile CTypes.Open trade wallet (expandedPhase == CTypes.Open) currentTime
                            , phaseElement dProfile CTypes.Committed trade wallet (expandedPhase == CTypes.Committed) currentTime
                            , phaseElement dProfile CTypes.Judgment trade wallet (expandedPhase == CTypes.Judgment) currentTime
                            ]
                        , paymentMethodElement dProfile trade.terms.paymentMethods
                        ]

                Mobile ->
                    Element.column
                        [ Element.width Element.fill
                        , Element.spacing 10
                        ]
                        [ phaseElement dProfile CTypes.Open trade wallet True currentTime
                        , phaseElement dProfile CTypes.Committed trade wallet True currentTime
                        , paymentMethodElement dProfile trade.terms.paymentMethods
                        , phaseElement dProfile CTypes.Judgment trade wallet True currentTime
                        ]


activePhaseAttributes =
    [ Element.Background.color EH.activePhaseBackgroundColor
    , Element.Font.color EH.white
    ]


inactivePhaseAttributes =
    [ Element.Background.color EH.white
    ]


phaseState : CTypes.FullTradeInfo -> CTypes.Phase -> PhaseState
phaseState trade phase =
    let
        ( viewPhaseInt, activePhaseInt ) =
            ( CTypes.phaseToInt phase
            , CTypes.phaseToInt trade.state.phase
            )
    in
    if viewPhaseInt > activePhaseInt then
        NotStarted

    else if viewPhaseInt == activePhaseInt then
        Active

    else
        Finished


phaseElement : DisplayProfile -> CTypes.Phase -> FullTradeInfo -> Wallet.State -> Bool -> Time.Posix -> Element Msg
phaseElement dProfile viewPhase trade wallet expanded currentTime =
    let
        commonPhaseAttributes =
            [ Element.Border.rounded (12 |> changeForMobile 8 dProfile)
            , Element.alignTop
            , Element.Border.shadow
                { offset = ( 0, 0 )
                , size = 0
                , blur = 8
                , color = Element.rgba 0 0 0 0.2
                }
            ]
                ++ (case dProfile of
                        Desktop ->
                            [ Element.height (Element.shrink |> Element.minimum 380) ]

                        Mobile ->
                            []
                   )

        viewPhaseState =
            phaseState trade viewPhase

        fullInterval =
            case viewPhase of
                CTypes.Open ->
                    trade.parameters.autorecallInterval

                CTypes.Committed ->
                    trade.parameters.autoabortInterval

                CTypes.Judgment ->
                    trade.parameters.autoreleaseInterval

                _ ->
                    Time.millisToPosix 0

        displayInterval =
            case viewPhaseState of
                NotStarted ->
                    fullInterval

                Active ->
                    TimeHelpers.sub
                        (TimeHelpers.add trade.state.phaseStartTime fullInterval)
                        currentTime

                Finished ->
                    Time.millisToPosix 0

        firstEl =
            phaseStatusElement
                dProfile
                viewPhase
                trade
                currentTime

        secondEl =
            Element.el
                [ Element.padding 10
                , Element.width Element.fill
                , Element.height Element.fill
                ]
                (phaseBodyElement dProfile viewPhase currentTime trade wallet)

        borderEl =
            Element.el
                ((case dProfile of
                    Desktop ->
                        [ Element.height Element.fill
                        , Element.width <| Element.px 1
                        ]

                    Mobile ->
                        [ Element.width Element.fill
                        , Element.height <| Element.px 1
                        ]
                 )
                    ++ [ Element.Background.color <|
                            case viewPhaseState of
                                Active ->
                                    Element.rgb 0 0 1

                                _ ->
                                    EH.lightGray
                       ]
                )
                Element.none
    in
    if expanded then
        (Element.row |> changeForMobile Element.column dProfile)
            (commonPhaseAttributes
                ++ (if viewPhaseState == Active then
                        activePhaseAttributes

                    else
                        inactivePhaseAttributes
                   )
                ++ [ Element.width Element.fill ]
            )
            [ firstEl, borderEl, secondEl ]

    else
        Element.row
            (commonPhaseAttributes
                ++ (if viewPhaseState == Active then
                        activePhaseAttributes

                    else
                        inactivePhaseAttributes
                   )
                ++ [ Element.pointer
                   , Element.Events.onClick <| ExpandPhase viewPhase
                   ]
            )
            [ firstEl ]


paymentMethodElement : DisplayProfile -> List PaymentMethod -> Element Msg
paymentMethodElement dProfile paymentMethods =
    let
        maybePmText =
            paymentMethods
                |> List.head
                |> Maybe.map .info
    in
    Element.column
        [ Element.Border.rounded 12
        , Element.Background.color <| EH.lightGray
        , Element.padding 15
        , Element.spacing 15
        , Element.centerX
        ]
        [ Element.el
            [ Element.Font.size (24 |> changeForMobile 20 dProfile)
            , Element.Font.semiBold
            , Element.Font.italic
            , Element.centerX
            ]
            (Element.text "Payment Method")
        , Element.el
            [ Element.Font.size (18 |> changeForMobile 12 dProfile)
            , Element.height Element.shrink
            , Element.Background.color <| EH.white
            , Element.Border.shadow
                { offset = ( -3, 3 )
                , size = 0
                , blur = 5
                , color = Element.rgba 0 0 0 0.2
                }
            , Element.Border.rounded 3
            , Element.padding 5
            ]
            (maybePmText
                |> Maybe.map (Markdown.toHtml Nothing)
                |> Maybe.map (List.map Element.html)
                |> Maybe.map (Element.paragraph [ Element.spacing 2 ])
                |> Maybe.withDefault
                    (Element.el [ Element.Font.color EH.disabledTextColor, Element.Font.italic ] <| Element.text "No payment methods found.")
            )
        ]


phaseStatusElement : DisplayProfile -> CTypes.Phase -> CTypes.FullTradeInfo -> Time.Posix -> Element Msg
phaseStatusElement dProfile viewPhase trade currentTime =
    let
        viewPhaseState =
            phaseState trade viewPhase

        titleColor =
            case viewPhaseState of
                Active ->
                    Element.rgb255 0 226 255

                _ ->
                    EH.black

        titleElement =
            Element.el
                [ Element.Font.color titleColor
                , Element.Font.size 20
                , Element.Font.semiBold
                ]
                (Element.text <|
                    case viewPhase of
                        CTypes.Open ->
                            "Open Window"

                        CTypes.Committed ->
                            "Payment Window"

                        CTypes.Judgment ->
                            "Burn Window"

                        CTypes.Closed ->
                            "Closed"
                )

        intervalElement =
            case viewPhase of
                CTypes.Closed ->
                    Element.none

                _ ->
                    case viewPhaseState of
                        NotStarted ->
                            EH.interval
                                [ Element.centerX ]
                                [ Element.Font.size (22 |> changeForMobile 14 dProfile)
                                , Element.Font.medium
                                ]
                                ( EH.black, EH.lightGray )
                                (CTypes.getPhaseInterval viewPhase trade)

                        Active ->
                            case CTypes.getCurrentPhaseTimeoutInfo currentTime trade of
                                CTypes.TimeLeft timeoutInfo ->
                                    EH.intervalWithElapsedBar
                                        [ Element.centerX ]
                                        [ Element.Font.size (22 |> changeForMobile 14 dProfile)
                                        , Element.Font.medium
                                        ]
                                        ( EH.white, EH.lightGray )
                                        timeoutInfo

                                CTypes.TimeUp _ ->
                                    Element.column
                                        [ Element.centerX
                                        , Element.spacing 10
                                        ]
                                        [ Element.el [ Element.centerX ] <| Element.text (CTypes.getPokeText viewPhase)
                                        , EH.blueButton dProfile [] [ "Poke" ] (StartContractAction Poke)
                                        ]

                        Finished ->
                            Element.el [ Element.height <| Element.px 1 ] Element.none
    in
    case dProfile of
        Desktop ->
            Element.column
                [ Element.padding 20
                , Element.spacing 10
                , Element.height Element.fill
                ]
                [ Element.el
                    [ Element.alignTop
                    , Element.centerX
                    ]
                    titleElement
                , Element.el
                    [ Element.height Element.fill
                    , Element.centerX
                    ]
                  <|
                    Element.el
                        [ Element.centerY
                        ]
                    <|
                        phaseIconElement dProfile viewPhase viewPhaseState
                , Element.column
                    [ Element.spacing 10
                    , Element.alignBottom
                    , Element.centerX
                    ]
                    [ Element.el [ Element.centerX ] <| phaseStateElement dProfile viewPhaseState
                    , intervalElement
                    ]
                ]

        Mobile ->
            Element.row
                [ Element.padding 10
                , Element.spaceEvenly
                , Element.width Element.fill
                ]
                [ Element.el
                    [ Element.centerY ]
                  <|
                    phaseIconElement dProfile viewPhase viewPhaseState
                , Element.column
                    [ Element.spacing 10
                    , Element.centerY
                    ]
                    [ Element.el [ Element.centerX ] titleElement
                    , Element.row
                        [ Element.spacing 10
                        , Element.centerX
                        ]
                        [ phaseStateElement dProfile viewPhaseState
                        , intervalElement
                        ]
                    ]
                ]


phaseIconElement : DisplayProfile -> CTypes.Phase -> PhaseState -> Element Msg
phaseIconElement dProfile viewPhase viewPhaseState =
    let
        circleColor =
            case viewPhaseState of
                NotStarted ->
                    Element.rgb255 10 33 108

                Active ->
                    Element.rgb255 0 100 170

                Finished ->
                    Element.rgb255 1 129 104

        circleElement =
            Collage.circle (50 |> changeForMobile 35 dProfile)
                |> Collage.filled (Collage.uniform (EH.elementColorToAvh4Color circleColor))
                |> Collage.Render.svg
                |> Element.html

        image =
            CTypes.phaseIconWhite viewPhase
    in
    Element.el
        [ Element.centerX
        , Element.inFront
            (Images.toElement
                [ Element.centerX
                , Element.centerY
                , Element.height <| Element.px (60 |> changeForMobile 40 dProfile)
                ]
                image
            )
        ]
        circleElement


phaseStateElement : DisplayProfile -> PhaseState -> Element Msg
phaseStateElement dProfile pState =
    let
        commonAttributes =
            [ Element.Font.italic
            , Element.Font.semiBold
            , Element.Font.size (20 |> changeForMobile 14 dProfile)
            ]
    in
    case pState of
        Active ->
            Element.el
                (commonAttributes
                    ++ [ Element.Font.color <| EH.softRed ]
                )
                (Element.text "Active")

        NotStarted ->
            Element.el
                (commonAttributes
                    ++ [ Element.Font.color <| EH.darkGray ]
                )
                (Element.text "Not Started")

        Finished ->
            Element.el
                commonAttributes
                (Element.text "Finished")


phaseBodyElement : DisplayProfile -> CTypes.Phase -> Time.Posix -> CTypes.FullTradeInfo -> Wallet.State -> Element Msg
phaseBodyElement dProfile viewPhase currentTime trade wallet =
    let
        phaseIsActive =
            viewPhase == trade.state.phase

        maybeBuyerOrSeller =
            Wallet.userInfo wallet
                |> Maybe.map .address
                |> Maybe.andThen (CTypes.getBuyerOrSeller trade)

        mainFontColor =
            if phaseIsActive then
                EH.white

            else
                EH.black

        makeParagraph =
            Element.paragraph
                [ Element.Font.color mainFontColor
                , Element.Font.size (18 |> changeForMobile 12 dProfile)
                , Element.Font.semiBold
                , Element.spacing 2
                ]

        emphasizedColor =
            if phaseIsActive then
                Element.rgb255 0 226 255

            else
                Element.rgb255 16 7 234

        emphasizedText =
            Element.el [ Element.Font.color emphasizedColor ] << Element.text

        scaryText =
            Element.el [ Element.Font.color EH.softRed ] << Element.text

        tradeAmountString =
            TokenValue.toConciseString trade.parameters.tradeAmount ++ " " ++ tokenUnitName trade.reference.factory

        priceString =
            Currencies.toString trade.terms.price

        buyerDepositString =
            TokenValue.toConciseString trade.parameters.buyerDeposit ++ " " ++ tokenUnitName trade.reference.factory

        tradePlusDepositString =
            (TokenValue.add
                trade.parameters.tradeAmount
                trade.parameters.buyerDeposit
                |> TokenValue.toConciseString
            )
                ++ " "
                ++ tokenUnitName trade.reference.factory

        abortPunishment =
            trade.parameters.abortPunishment

        abortPunishmentString =
            TokenValue.toConciseString
                abortPunishment
                ++ " "
                ++ tokenUnitName trade.reference.factory

        sellerAbortRefundString =
            TokenValue.toConciseString
                (TokenValue.sub
                    trade.parameters.tradeAmount
                    abortPunishment
                )
                ++ " "
                ++ tokenUnitName trade.reference.factory

        buyerAbortRefundString =
            TokenValue.toConciseString
                (TokenValue.sub
                    trade.parameters.buyerDeposit
                    abortPunishment
                )
                ++ " "
                ++ tokenUnitName trade.reference.factory

        threeFlames =
            Element.row []
                (List.repeat 3
                    (Images.toElement
                        [ Element.height <| Element.px (18 |> changeForMobile 12 dProfile) ]
                        Images.flame
                    )
                )

        ( titleString, paragraphEls ) =
            case ( viewPhase, maybeBuyerOrSeller ) of
                ( CTypes.Open, Nothing ) ->
                    ( "Get it while it's hot"
                    , case trade.parameters.initiatorRole of
                        Seller ->
                            List.map makeParagraph
                                [ [ Element.text "The Seller has deposited "
                                  , emphasizedText tradeAmountString
                                  , Element.text " into this contract, and offers to sell it for "
                                  , emphasizedText priceString
                                  , Element.text ". To become the Buyer, you must deposit 1/3 of the trade amount "
                                  , emphasizedText <| "(" ++ buyerDepositString ++ ")"
                                  , Element.text " into this contract by clicking "
                                  , scaryText "Deposit and Commit to Trade"
                                  , Element.text "."
                                  ]
                                , [ Element.text <| "If the trade is successful, the combined " ++ tokenUnitName trade.reference.factory ++ " balance "
                                  , emphasizedText <| "(" ++ tradePlusDepositString ++ ")"
                                  , Element.text " will be released to you. If anything goes wrong, there are "
                                  , scaryText "burnable punishments "
                                  , threeFlames
                                  , Element.text " for both parties (see Payment Window for more on this)."
                                  ]
                                , [ Element.text "Don't commit unless you can fulfil one of the seller’s accepted payment methods below for "
                                  , emphasizedText priceString
                                  , Element.text " within the payment window."
                                  ]
                                ]

                        Buyer ->
                            List.map makeParagraph
                                [ [ Element.text "The Buyer is offering to buy "
                                  , emphasizedText tradeAmountString
                                  , Element.text " for "
                                  , emphasizedText priceString
                                  , Element.text ", and has deposited "
                                  , emphasizedText buyerDepositString
                                  , Element.text " into this contract as a "
                                  , scaryText "burnable deposit"
                                  , Element.text ". To become the Seller, deposit "
                                  , emphasizedText tradeAmountString
                                  , Element.text " into this contract by clicking "
                                  , scaryText "Deposit and Commit to Trade"
                                  , Element.text "."
                                  ]
                                , [ Element.text "When you receive the "
                                  , emphasizedText priceString
                                  , Element.text <| " from the Buyer, the combined " ++ tokenUnitName trade.reference.factory ++ " balance "
                                  , emphasizedText <| "(" ++ tradePlusDepositString ++ ")"
                                  , Element.text " will be released to the Buyer. If anything goes wrong, there are "
                                  , scaryText "burnable punishments "
                                  , threeFlames
                                  , Element.text " for both parties (see Payment Window for more on this)."
                                  ]
                                , [ Element.text "Don't commit unless you can receive "
                                  , emphasizedText priceString
                                  , Element.text " via one of the Buyer's payment methods below, within the payment window."
                                  ]
                                ]
                    )

                ( CTypes.Open, Just buyerOrSeller ) ->
                    ( "And Now, We Wait"
                    , case buyerOrSeller of
                        Buyer ->
                            List.map makeParagraph
                                [ [ Element.text "Your "
                                  , scaryText "burnable deposit"
                                  , Element.text " of "
                                  , emphasizedText buyerDepositString
                                  , Element.text " is now held in this contract, and your offer to buy "
                                  , emphasizedText tradeAmountString
                                  , Element.text " for "
                                  , emphasizedText priceString
                                  , Element.text " is now listed in the marketplace."
                                  ]
                                , [ Element.text "If another user likes your offer, they can become the Seller by depositing the full "
                                  , emphasizedText tradeAmountString
                                  , Element.text " into this contract."
                                  ]
                                , [ Element.text "If no one commits within the Open Window, your offer will expire, refunding the "
                                  , emphasizedText buyerDepositString
                                  , Element.text " to you."
                                  ]
                                ]

                        Seller ->
                            List.map makeParagraph
                                [ [ Element.text "Your offer to sell the "
                                  , emphasizedText tradeAmountString
                                  , Element.text " held in this contract for "
                                  , emphasizedText priceString
                                  , Element.text " is now listed in the marketplace."
                                  ]
                                , [ Element.text "If another user likes your offer, they can become the Buyer by depositing a "
                                  , scaryText "burnable deposit"
                                  , Element.text " of 1/3 of the trade amount "
                                  , emphasizedText <| "(" ++ buyerDepositString ++ ")"
                                  , Element.text " into this contract."
                                  ]
                                , [ Element.text "If no one commits within the Open Window, your offer will expire, refunding the "
                                  , emphasizedText tradeAmountString
                                  , Element.text " to you."
                                  ]
                                ]
                    )

                ( CTypes.Committed, Just Buyer ) ->
                    ( "Time to Pay Up"
                    , List.map makeParagraph
                        [ [ Element.text "You must now pay the Seller "
                          , emphasizedText priceString
                          , Element.text " via the Payment Method, "
                          , Element.el [ Element.Font.semiBold ] <| Element.text "and then click "
                          , scaryText "Confirm Payment"
                          , Element.text " before the payment window runs out. Use the chat to coordinate."
                          ]
                        , [ Element.text "If you abort the trade, or do not confirm payment before this time is up, "
                          , emphasizedText abortPunishmentString
                          , Element.text " (1/4 of the "
                          , scaryText "burnable deposit"
                          , Element.text ") will be "
                          , scaryText "burned"
                          , Element.text " from both parties, while the remainder of each party's deposit is refunded ("
                          , emphasizedText sellerAbortRefundString
                          , Element.text " to the Seller, "
                          , emphasizedText buyerAbortRefundString
                          , Element.text " to you)."
                          ]
                        , [ Element.text "This may be your last chance to clear up any ambiguity before Judgement. Do not confirm unless you're sure the "
                          , emphasizedText priceString
                          , Element.text " has been unmistakably transferred."
                          ]
                        ]
                    )

                ( CTypes.Committed, Just Seller ) ->
                    ( "Time to Get Paid"
                    , List.map makeParagraph
                        [ [ Element.text "Work with the Buyer to receive "
                          , emphasizedText priceString
                          , Element.text " as described in Payment Method, using the DAIHard encrypted chat as necessary. Then, the Buyer should confirm the payment, moving the trade to the final phase."
                          ]
                        , [ Element.text "If the Buyer aborts the trade, or doesn't confirm payment before this time is up, "
                          , emphasizedText abortPunishmentString
                          , Element.text " (1/4 of the "
                          , scaryText "burnable deposit"
                          , Element.text ") will be "
                          , scaryText "burned"
                          , Element.text " from both parties, while the remainder of each party's deposit is refunded ("
                          , emphasizedText sellerAbortRefundString
                          , Element.text " to you, "
                          , emphasizedText buyerAbortRefundString
                          , Element.text " to the Buyer)."
                          ]
                        ]
                    )

                ( CTypes.Committed, Nothing ) ->
                    ( "Making the Payment"
                    , List.map makeParagraph
                        [ [ Element.text "During this phase, the Buyer is expected to transfer "
                          , emphasizedText priceString
                          , Element.text " to the Seller, as described in Payment Method, "
                          , Element.el [ Element.Font.semiBold ] <| Element.text "and "
                          , scaryText "Confirm the Payment "
                          , Element.text " before the payment window runs out. This would move the trade to the final phase."
                          ]
                        , [ Element.text "DAIHard encrypted chat will be available to the Buyer and Seller, for coordination." ]
                        , [ Element.text "If the Buyer aborts the trade, or doesn't confirm payment before this time is up, "
                          , emphasizedText abortPunishmentString
                          , Element.text " (1/4 of the "
                          , scaryText "burnable deposit"
                          , Element.text " amount) will be "
                          , scaryText "burned"
                          , Element.text " from both parties, while the remainder of each party's deposit is refunded ("
                          , emphasizedText sellerAbortRefundString
                          , Element.text " to the Seller, "
                          , emphasizedText buyerAbortRefundString
                          , Element.text " to the Buyer)."
                          ]
                        ]
                    )

                ( CTypes.Judgment, Just Buyer ) ->
                    ( "Judgement"
                    , List.map makeParagraph
                        [ [ Element.text "If the Seller confirms receipt of payment, or makes no decision within the Burn Window, the combined balance of "
                          , emphasizedText tradePlusDepositString
                          , Element.text " is yours to claim."
                          ]
                        , [ Element.text "If they cannot confirm they've received payment from you, they will probably choose to "
                          , scaryText "burn the contract's balance of "
                          , emphasizedText tradePlusDepositString
                          , scaryText "."
                          , Element.text " In this case the "
                          , emphasizedText tradePlusDepositString
                          , Element.text " will be lost to both parties."
                          ]
                        , [ Element.text "These are the only options the Seller has. So, fingers crossed!"
                          ]
                        ]
                    )

                ( CTypes.Judgment, Just Seller ) ->
                    ( "Judgement"
                    , List.map makeParagraph
                        [ [ Element.text "By pushing the contract to the final stage, the Buyer has indicated that the transfer has taken place, and awaits your judgement."
                          ]
                        , [ Element.text "So, have you recieved the "
                          , emphasizedText priceString
                          , Element.text "? If so, you can click "
                          , emphasizedText "Release Everything"
                          , Element.text "."
                          ]
                        , [ Element.text "If not, the Buyer is probably trying to scam you, and you should probably "
                          , scaryText "burn it all"
                          , Element.text ". You're not getting it back either way, and you wouldn't want the other guy to get it, would you?"
                          ]
                        , [ Element.text "If you don't decide within the Burn Window, the Buyer will be able to claim the full balance."
                          ]
                        ]
                    )

                ( CTypes.Judgment, Nothing ) ->
                    ( "Judgement"
                    , List.map makeParagraph
                        [ [ Element.text "The Buyer has indicated that the transfer has taken place, and awaits the Seller's judgement on the fact of the matter."
                          ]
                        , [ Element.text "If the Seller can verify he has received the "
                          , emphasizedText priceString
                          , Element.text ", he will probably release the total balance of "
                          , emphasizedText tradeAmountString
                          , Element.text " to the Buyer. If he cannot verify payment, he will probably instead "
                          , scaryText "burn it all"
                          , Element.text "."
                          ]
                        , [ Element.text "If the Seller has not made a decision before the Burn Window expires, the "
                          , emphasizedText tradeAmountString
                          , Element.text " becomes claimable by the Buyer."
                          ]
                        ]
                    )

                ( CTypes.Closed, Just _ ) ->
                    ( "Contract closed."
                    , [ makeParagraph [ Element.text "Check the chat log for the full history." ] ]
                    )

                ( CTypes.Closed, Nothing ) ->
                    ( "Contract closed."
                    , []
                    )
    in
    Element.column
        [ Element.width Element.fill
        , Element.height Element.fill
        , Element.padding (20 |> changeForMobile 10 dProfile)
        , Element.spacing (30 |> changeForMobile 20 dProfile)
        ]
        [ Element.el
            [ Element.Font.size (24 |> changeForMobile 16 dProfile)
            , Element.Font.semiBold
            , Element.Font.color emphasizedColor
            , Element.alignLeft
            ]
            (Element.text titleString)
        , Element.column
            [ Element.width Element.fill
            , Element.centerY
            , Element.spacing (13 |> changeForMobile 10 dProfile)
            ]
            paragraphEls
        , Element.el
            [ Element.alignRight |> changeForMobile Element.centerX dProfile
            ]
            (case phaseState trade viewPhase of
                Active ->
                    actionButtonsElement dProfile currentTime trade wallet

                NotStarted ->
                    Element.el
                        [ Element.Font.size 20
                        , Element.Font.semiBold
                        , Element.Font.italic
                        , Element.Font.color EH.darkGray
                        ]
                        (Element.text "Phase not yet started.")

                Finished ->
                    Element.el
                        [ Element.Font.size 20
                        , Element.Font.semiBold
                        , Element.Font.italic
                        ]
                        (Element.text "Phase no longer active.")
            )
        ]


actionButtonsElement : DisplayProfile -> Time.Posix -> FullTradeInfo -> Wallet.State -> Element Msg
actionButtonsElement dProfile currentTime trade wallet =
    case Wallet.userInfo wallet of
        Just userInfo ->
            if Wallet.networkForFactory trade.reference.factory /= userInfo.network then
                Element.paragraph
                    [ Element.Font.size 18
                    , Element.Font.italic
                    , Element.Font.color EH.darkGray
                    ]
                    [ Element.text <|
                        "You must connect to the "
                            ++ networkNameForFactory trade.reference.factory
                            ++ " network to interact with this trade."
                    ]

            else
                case CTypes.getCurrentPhaseTimeoutInfo currentTime trade of
                    CTypes.TimeUp _ ->
                        Element.none

                    CTypes.TimeLeft _ ->
                        (Element.row |> changeForMobile Element.column dProfile)
                            [ Element.spacing 8 ]
                            (case
                                ( trade.state.phase
                                , CTypes.getInitiatorOrResponder trade userInfo.address
                                , CTypes.getBuyerOrSeller trade userInfo.address
                                )
                             of
                                ( CTypes.Open, Just Initiator, _ ) ->
                                    [ Element.map StartContractAction <| EH.blueButton dProfile [] [ "Remove and Refund this Trade" ] Recall ]

                                ( CTypes.Open, Nothing, _ ) ->
                                    let
                                        depositAmount =
                                            CTypes.responderDeposit trade.parameters
                                                |> TokenValue.getEvmValue
                                    in
                                    [ EH.redButton dProfile [] [ "Deposit and Commit to Trade" ] <| CommitClicked trade userInfo depositAmount ]

                                ( CTypes.Committed, _, Just Buyer ) ->
                                    [ Element.map ContractActionClicked <| EH.orangeButton dProfile [] [ "Abort Trade" ] Abort
                                    , Element.map ContractActionClicked <| EH.redButton dProfile [] [ "Confirm Payment" ] Claim
                                    , chatHistoryButton
                                    ]

                                ( CTypes.Committed, _, Just Seller ) ->
                                    [ chatHistoryButton ]

                                ( CTypes.Judgment, _, Just Seller ) ->
                                    [ Element.map ContractActionClicked <| EH.redButton dProfile [] [ "Burn it All!" ] Burn
                                    , Element.map ContractActionClicked <| EH.blueButton dProfile [] [ "Release Everything" ] Release
                                    , chatHistoryButton
                                    ]

                                ( CTypes.Judgment, _, Just Buyer ) ->
                                    [ chatHistoryButton ]

                                _ ->
                                    []
                            )

        Nothing ->
            EH.redButton dProfile [] [ "Connect to Wallet" ] Web3Connect


chatHistoryButton : Element Msg
chatHistoryButton =
    Element.el
        [ Element.Border.rounded 4
        , Element.pointer
        , EH.onClickNoPropagation ToggleChat
        , Element.padding 5
        , Element.Background.color <| Element.rgb255 22 0 255
        ]
    <|
        Images.toElement
            [ Element.width <| Element.px 42
            ]
            Images.chatIcon


chatOverlayElement : DisplayProfile -> Model -> Element Msg
chatOverlayElement dProfile model =
    case ( model.showChatHistory, model.chatHistoryModel ) of
        ( True, Just chatHistoryModel ) ->
            case dProfile of
                Mobile ->
                    EH.closeableModalBlackX
                        [ Element.width Element.fill
                        , Element.height Element.fill
                        ]
                        (Element.map
                            ChatHistoryMsg
                            (ChatHistory.window dProfile chatHistoryModel)
                        )
                        NoOp
                        ToggleChat
                        False

                Desktop ->
                    Element.el
                        [ Element.height Element.fill
                        , Element.width <| Element.px 500
                        , Element.padding 20
                        , Element.alignRight
                        ]
                    <|
                        EH.closeableModalBlackX
                            [ Element.height Element.fill
                            , Element.width Element.fill
                            ]
                            (Element.map
                                ChatHistoryMsg
                                (ChatHistory.window dProfile chatHistoryModel)
                            )
                            NoOp
                            ToggleChat
                            False

        _ ->
            Element.none


getTxModalOrNone : DisplayProfile -> Model -> Element Msg
getTxModalOrNone dProfile model =
    case ( model.txChainStatus, model.trade ) of
        ( Just txChainStatus, CTypes.LoadedTrade trade ) ->
            let
                confirmAbortAttributes =
                    if txChainStatus.confirmingAbort then
                        let
                            message =
                                case txChainStatus.mode of
                                    ConfirmingCommit _ _ ->
                                        ""

                                    ApproveNeedsSig ->
                                        ""

                                    ConfirmingAction _ ->
                                        ""

                                    ActionNeedsSig _ ->
                                        ""

                                    ApproveMining _ ->
                                        "If you abort now, your deposit will not complete and you won't commit to the offer."

                                    CommitNeedsSig ->
                                        "If you abort now, your deposit will not complete and you won't commit to the offer."

                                    CommitMining _ ->
                                        "Aborting now WILL NOT PREVENT the deposit and commitment; it will only return you to the Trade page. You may be able to cancel the transaciton in your web3 wallet."

                                    ActionMining _ _ ->
                                        "Aborting now WILL NOT CANCEL this action! You may be able to cancel the transaction via your web3 wallet."
                        in
                        [ Element.inFront <|
                            Element.column
                                [ Element.centerX
                                , Element.centerY
                                , Element.padding 10
                                , Element.spacing 10
                                , Element.Border.rounded 5
                                , Element.Background.color EH.white
                                ]
                                [ Element.paragraph
                                    [ Element.width Element.fill ]
                                    [ Element.text message ]
                                , Element.row
                                    [ Element.centerX
                                    , Element.spacing 10
                                    ]
                                    [ EH.redButton
                                        dProfile
                                        []
                                        [ "Abort" ]
                                        ConfirmCloseTxModalClicked
                                    , EH.blueButton
                                        dProfile
                                        []
                                        [ "Nevermind" ]
                                        NevermindCloseTxModalClicked
                                    ]
                                ]
                        ]

                    else
                        []
            in
            case txChainStatus.mode of
                ConfirmingCommit userInfo deposit ->
                    let
                        depositAmountString =
                            TokenValue.tokenValue deposit
                                |> TokenValue.toConciseString

                        priceString =
                            Currencies.toString trade.terms.price

                        daiAmountString =
                            TokenValue.toConciseString trade.parameters.tradeAmount ++ " " ++ tokenUnitName trade.reference.factory

                        ( buyerOrSellerEl, agreeToWhatTextList ) =
                            case CTypes.getResponderRole trade.parameters of
                                Buyer ->
                                    ( Element.el [ Element.Font.medium, Element.Font.color EH.black ] <| Element.text "buyer"
                                    , [ Element.text "pay the seller "
                                      , Element.el [ Element.Font.color EH.blue ] <| Element.text priceString
                                      , Element.text " in exchange for the "
                                      , Element.el [ Element.Font.color EH.blue ] <| Element.text daiAmountString
                                      , Element.text " held in this contract."
                                      ]
                                    )

                                Seller ->
                                    ( Element.el [ Element.Font.medium, Element.Font.color EH.black ] <| Element.text "seller"
                                    , [ Element.text "accept "
                                      , Element.el [ Element.Font.color EH.blue ] <| Element.text priceString
                                      , Element.text " from the buyer in exchange for the "
                                      , Element.el [ Element.Font.color EH.blue ] <| Element.text daiAmountString
                                      , Element.text " held in this contract."
                                      ]
                                    )
                    in
                    EH.closeableModalBlackX
                        []
                        (Element.column
                            [ Element.spacing (20 |> changeForMobile 10 dProfile)
                            , Element.padding (20 |> changeForMobile 10 dProfile)
                            , Element.centerX
                            , Element.height Element.fill
                            , Element.Font.center
                            ]
                            [ Element.el
                                [ Element.Font.size (26 |> changeForMobile 22 dProfile)
                                , Element.Font.semiBold
                                , Element.centerX
                                , Element.centerY
                                ]
                                (Element.text "Just to Confirm...")
                            , Element.column
                                [ Element.spacing (20 |> changeForMobile 10 dProfile)
                                , Element.centerX
                                , Element.centerY
                                ]
                                (List.map
                                    (Element.paragraph
                                        [ Element.centerX
                                        , Element.Font.size (18 |> changeForMobile 16 dProfile)
                                        , Element.Font.medium
                                        , Element.Font.color EH.permanentTextColor
                                        , Element.spacing 2
                                        ]
                                    )
                                    ([ [ Element.text <| "You will deposit "
                                       , Element.el [ Element.Font.color EH.blue ] <| Element.text <| depositAmountString ++ " " ++ tokenUnitName trade.reference.factory
                                       , Element.text ", thereby becoming the "
                                       , buyerOrSellerEl
                                       , Element.text " of this trade. By doing so, you are agreeing to "
                                       ]
                                        ++ agreeToWhatTextList
                                     ]
                                        ++ (case trade.reference.factory of
                                                Token _ ->
                                                    [ [ Element.text <| "(This ususally requires two web3 signatures. Your " ++ tokenUnitName trade.reference.factory ++ " will not be deposited until the second transaction has been mined.)" ] ]

                                                _ ->
                                                    []
                                           )
                                    )
                                )
                            , Element.el
                                [ Element.alignBottom
                                , Element.centerX
                                ]
                                (EH.redButton
                                    dProfile
                                    []
                                    (case dProfile of
                                        Desktop ->
                                            [ "Yes, I definitely want to commit to this trade." ]

                                        Mobile ->
                                            [ "Yes, I definitely want", "to commit to this trade." ]
                                    )
                                    (ConfirmCommit trade userInfo deposit)
                                )
                            ]
                        )
                        NoOp
                        CloseTxModalClicked
                        False

                ApproveNeedsSig ->
                    Element.el
                        (confirmAbortAttributes
                            ++ [ Element.centerX
                               , Element.centerY
                               ]
                        )
                    <|
                        EH.txProcessModal
                            [ Element.text "Waiting for user signature for the approve call."
                            , Element.text "(check your web3 wallet!)"
                            , Element.text "Note that there will be a second transaction to sign after this."
                            ]
                            NoOp
                            CloseTxModalClicked
                            NoOp

                ApproveMining txHash ->
                    Element.el
                        (confirmAbortAttributes
                            ++ [ Element.centerX
                               , Element.centerY
                               ]
                        )
                    <|
                        EH.txProcessModal
                            [ Element.text "Mining the initial approve transaction..."
                            , Element.newTabLink [ Element.Font.underline, Element.Font.color EH.blue ]
                                { url = EthHelpers.makeViewTxUrl trade.reference.factory txHash
                                , label = Element.text "See the transaction on Etherscan"
                                }
                            , Element.text "Funds will not leave your wallet until you sign the next transaction."
                            ]
                            NoOp
                            CloseTxModalClicked
                            NoOp

                CommitNeedsSig ->
                    Element.el
                        (confirmAbortAttributes
                            ++ [ Element.centerX
                               , Element.centerY
                               ]
                        )
                    <|
                        EH.txProcessModal
                            [ Element.text "Waiting for user signature for the final commit call."
                            , Element.text "(check your web3 wallet!)"
                            , Element.text "This will make the deposit and commit you to the trade."
                            ]
                            NoOp
                            CloseTxModalClicked
                            NoOp

                CommitMining txHash ->
                    Element.el
                        (confirmAbortAttributes
                            ++ [ Element.centerX
                               , Element.centerY
                               ]
                        )
                    <|
                        EH.txProcessModal
                            [ Element.text "Mining the final commit transaction..."
                            , Element.newTabLink [ Element.Font.underline, Element.Font.color EH.blue ]
                                { url = EthHelpers.makeViewTxUrl trade.reference.factory txHash
                                , label = Element.text "See the transaction"
                                }
                            ]
                            NoOp
                            CloseTxModalClicked
                            NoOp

                ConfirmingAction action ->
                    EH.closeableModalBlackX
                        confirmAbortAttributes
                        (Element.column
                            [ Element.spacing 20
                            , Element.padding 20
                            , Element.centerX
                            , Element.height Element.fill
                            , Element.Font.center
                            ]
                            [ Element.el
                                [ Element.Font.size 26
                                , Element.Font.semiBold
                                , Element.centerX
                                , Element.centerY
                                ]
                                (Element.text "Just to Confirm...")
                            , Element.column
                                [ Element.spacing (20 |> changeForMobile 10 dProfile)
                                , Element.centerX
                                , Element.centerY
                                ]
                                (List.map
                                    (Element.paragraph
                                        [ Element.centerX
                                        , Element.Font.size (18 |> changeForMobile 16 dProfile)
                                        , Element.Font.medium
                                        , Element.Font.color EH.permanentTextColor
                                        , Element.spacing 2
                                        ]
                                    )
                                    (case action of
                                        Poke ->
                                            []

                                        Recall ->
                                            []

                                        Claim ->
                                            [ [ Element.text <| "By clicking \"Confirm Payment\", you are claiming that you've paid the Seller in a way they can verify. Only do this if you are sure the Seller will agree that they have the money--otherwise they may burn the " ++ tokenUnitName trade.reference.factory ++ " rather than release it to you." ] ]

                                        Abort ->
                                            [ [ Element.text <| "Aborting will incur a small penalty on both parties, and refund the rest of the " ++ tokenUnitName trade.reference.factory ++ "." ] ]

                                        Release ->
                                            [ [ Element.text "Releasing the payment will irreversibly send the trade's balance to the Buyer. Only do this if you are certain you've received the full agreed-upon payment." ] ]

                                        Burn ->
                                            [ [ Element.text <| "This will destroy the " ++ tokenUnitName trade.reference.factory ++ " in the payment. Only do this if the Buyer has attempted to scam you, is nonresponsive, or for some reason has failed the payment." ] ]
                                    )
                                )
                            , Element.el
                                [ Element.alignBottom
                                , Element.centerX
                                ]
                                ((case action of
                                    Poke ->
                                        "Poke"

                                    Recall ->
                                        "Recall"

                                    Claim ->
                                        "I understand. Confirm Payment"

                                    Abort ->
                                        "I understand. Abort the trade."

                                    Release ->
                                        "I understand. Release the " ++ tokenUnitName trade.reference.factory ++ "."

                                    Burn ->
                                        "I understand. Burn the " ++ tokenUnitName trade.reference.factory ++ "."
                                 )
                                    |> (\s -> EH.redButton dProfile [] [ s ] (StartContractAction action))
                                )
                            ]
                        )
                        NoOp
                        CloseTxModalClicked
                        False

                ActionNeedsSig action ->
                    Element.el
                        (confirmAbortAttributes
                            ++ [ Element.centerX
                               , Element.centerY
                               ]
                        )
                    <|
                        EH.txProcessModal
                            [ Element.text <| "Waiting for user signature for the " ++ actionName action ++ " call."
                            , Element.text "(check your web3 wallet!)"
                            ]
                            NoOp
                            CloseTxModalClicked
                            NoOp

                ActionMining action txHash ->
                    Element.none

        ( Nothing, _ ) ->
            Element.none

        ( _, _ ) ->
            Element.none


closedReasonToText : CTypes.ClosedReason -> String
closedReasonToText reason =
    case reason of
        CTypes.NotClosed ->
            ""

        CTypes.Recalled ->
            "Recalled"

        CTypes.Aborted ->
            "Aborted"

        CTypes.Released ->
            "Released"

        CTypes.Burned ->
            "Burned"
