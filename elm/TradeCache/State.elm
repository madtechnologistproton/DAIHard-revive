module TradeCache.State exposing (init, initAndStartCaching, loadedValidTrades, startCaching, subscriptions, update)

import Array exposing (Array)
import BigInt exposing (BigInt)
import CmdUp exposing (CmdUp)
import CommonTypes exposing (..)
import Contracts.Types as CTypes
import Contracts.Wrappers
import Dict exposing (Dict)
import Eth.Sentry.Event as EventSentry
import Helpers.BigInt as BigIntHelpers
import Helpers.Eth as EthHelpers
import List.Extra
import Maybe.Extra
import PaymentMethods exposing (PaymentMethod)
import Time
import TradeCache.Types exposing (..)
import UserNotice as UN exposing (UserNotice)


init : FactoryType -> ( TradeCache, Cmd Msg, List (CmdUp Msg) )
init factoryType =
    let
        ( sentry, sentryCmd ) =
            EventSentry.init
                EventSentryMsg
                (EthHelpers.httpProviderForFactory factoryType)
    in
    ( { factory = factoryType
      , eventSentry = sentry
      , trades = Array.empty
      , dataFetchState =
            DataState Nothing 0 0
      }
    , sentryCmd
    , [ CmdUp.gTag "tradeCache init" "processing" (factoryName factoryType) 0 ]
    )


startCaching : TradeCache -> Cmd Msg
startCaching tradeCache =
    Contracts.Wrappers.getNumTradesCmd tradeCache.factory InitialNumTradesFetched


initAndStartCaching : FactoryType -> ( TradeCache, Cmd Msg, List (CmdUp Msg) )
initAndStartCaching factoryType =
    let
        ( tc, cmd1, cmdUps ) =
            init factoryType
    in
    ( tc
    , Cmd.batch
        [ cmd1
        , startCaching tc
        ]
    , cmdUps
    )


updateStates : List Int -> TradeCache -> Cmd Msg
updateStates tradeIds tradeCache =
    tradeIds
        |> List.map
            (\id ->
                Array.get id tradeCache.trades
                    |> Maybe.andThen CTypes.tradeAddress
                    |> Maybe.map (\address -> ( id, address ))
            )
        |> Maybe.Extra.values
        |> List.map
            (\( id, address ) ->
                Contracts.Wrappers.getStateCmd tradeCache.factory address (StateFetched id)
            )
        |> Cmd.batch


update : Msg -> TradeCache -> UpdateResult
update msg prevModel =
    case msg of
        InitialNumTradesFetched fetchResult ->
            case fetchResult of
                Ok bigInt ->
                    let
                        numTrades =
                            BigIntHelpers.toIntWithWarning bigInt

                        fetchCreationInfoCmd =
                            Cmd.batch
                                (List.range 0 (numTrades - 1)
                                    |> List.map
                                        (\id ->
                                            Contracts.Wrappers.getCreationInfoFromIdCmd prevModel.factory (BigInt.fromInt id) (CreationInfoFetched id)
                                        )
                                )

                        trades =
                            List.range 0 (numTrades - 1)
                                |> List.map (CTypes.partialTradeInfo << TradeReference prevModel.factory)
                                |> Array.fromList
                    in
                    UpdateResult
                        { prevModel
                            | trades = trades
                            , dataFetchState = DataState (Just numTrades) 0 0
                        }
                        fetchCreationInfoCmd
                        []

                Err errstr ->
                    UpdateResult
                        prevModel
                        Cmd.none
                        [ CmdUp.UserNotice <|
                            UN.web3FetchError "Factory numTrades" errstr
                        ]

        CheckForNewTrades ->
            UpdateResult
                prevModel
                (Contracts.Wrappers.getNumTradesCmd prevModel.factory NumTradesFetchedAgain)
                []

        UpdateTradePhases ->
            let
                updatePhasesCmd =
                    loadedTrades prevModel
                        |> List.map
                            (\trade ->
                                case trade.state.phase of
                                    CTypes.Closed ->
                                        Nothing

                                    _ ->
                                        Just <|
                                            Contracts.Wrappers.getPhaseCmd
                                                trade.reference.factory
                                                trade.creationInfo.address
                                                (PhaseFetched trade.reference.factory trade.reference.id)
                            )
                        |> Maybe.Extra.values
                        |> Cmd.batch
            in
            UpdateResult
                prevModel
                updatePhasesCmd
                []

        PhaseFetched factory id fetchResult ->
            case fetchResult of
                Ok (Just newPhase) ->
                    let
                        intermediateUpdateResult =
                            prevModel
                                |> updateTradePhase id newPhase

                        ( cmd, cmdUps ) =
                            case ( newPhase, Array.get id prevModel.trades ) of
                                ( CTypes.Committed, Just trade ) ->
                                    case CTypes.getCreationInfo trade of
                                        Just creationInfo ->
                                            -- state has changed; update
                                            ( Contracts.Wrappers.getStateCmd
                                                factory
                                                creationInfo.address
                                                (StateFetched id)
                                            , []
                                            )

                                        Nothing ->
                                            ( Cmd.none
                                            , [ CmdUp.UserNotice <|
                                                    UN.unexpectedError "Phase fetched for a trade that has no creationInfo" trade
                                              ]
                                            )

                                ( _, Nothing ) ->
                                    ( Cmd.none
                                    , [ CmdUp.UserNotice <|
                                            UN.unexpectedError "Phase fetched for a trade, but then ran into an out-of-range error" Nothing
                                      ]
                                    )

                                _ ->
                                    ( Cmd.none
                                    , []
                                    )
                    in
                    UpdateResult
                        intermediateUpdateResult.tradeCache
                        (Cmd.batch
                            [ intermediateUpdateResult.cmd
                            , cmd
                            ]
                        )
                        (List.append
                            intermediateUpdateResult.cmdUps
                            cmdUps
                        )

                badFetchResult ->
                    UpdateResult
                        prevModel
                        Cmd.none
                        [ CmdUp.UserNotice <|
                            UN.fromBadFetchResultMaybe "phase" fetchResult
                        ]

        NumTradesFetchedAgain fetchResult ->
            case ( fetchResult, prevModel.dataFetchState.total ) of
                ( Ok bigInt, Just oldNumTrades ) ->
                    let
                        newNumTrades =
                            BigIntHelpers.toIntWithWarning bigInt
                    in
                    if oldNumTrades < newNumTrades then
                        let
                            fetchCreationInfoCmd =
                                Cmd.batch
                                    (List.range oldNumTrades (newNumTrades - 1)
                                        |> List.map
                                            (\id ->
                                                Contracts.Wrappers.getCreationInfoFromIdCmd prevModel.factory (BigInt.fromInt id) (CreationInfoFetched id)
                                            )
                                    )

                            additionalTrades =
                                List.range oldNumTrades (newNumTrades - 1)
                                    |> List.map (CTypes.partialTradeInfo << TradeReference prevModel.factory)
                                    |> Array.fromList

                            oldState =
                                prevModel.dataFetchState
                        in
                        UpdateResult
                            { prevModel
                                | trades = Array.append prevModel.trades additionalTrades
                                , dataFetchState = { oldState | total = Just newNumTrades }
                            }
                            fetchCreationInfoCmd
                            []

                    else
                        justModelUpdate prevModel

                ( Err errstr, _ ) ->
                    UpdateResult
                        prevModel
                        Cmd.none
                        [ CmdUp.UserNotice <|
                            UN.web3FetchError "Factory numTrades" errstr
                        ]

                ( _, Nothing ) ->
                    UpdateResult
                        prevModel
                        Cmd.none
                        [ CmdUp.UserNotice <|
                            UN.unexpectedError "Trying to fetch additional trades, but there is an unexpected Nothing in the existing numTrades." ""
                        ]

        CreationInfoFetched id fetchResult ->
            case fetchResult of
                Ok encodedCreationInfo ->
                    let
                        creationInfo =
                            CTypes.TradeCreationInfo
                                encodedCreationInfo.address_
                                (BigIntHelpers.toIntWithWarning encodedCreationInfo.blocknum)

                        ( newModel, notices ) =
                            prevModel
                                |> updateTradeCreationInfo id creationInfo

                        ( newSentry, sentryCmd ) =
                            Contracts.Wrappers.getInitiatedEventDataSentryCmd prevModel.eventSentry creationInfo (InitiatedEventDataFetched id)

                        cmd =
                            Cmd.batch
                                [ Contracts.Wrappers.getParametersStateAndPhaseInfoCmd prevModel.factory creationInfo.address (ParametersFetched id) (StateFetched id) (PhaseStartInfoFetched id)
                                , sentryCmd
                                ]
                    in
                    UpdateResult
                        ({ newModel | eventSentry = newSentry }
                            |> updateStatus
                        )
                        cmd
                        (notices |> List.map CmdUp.UserNotice)

                Err errstr ->
                    UpdateResult
                        prevModel
                        Cmd.none
                        [ CmdUp.UserNotice <|
                            UN.web3FetchError "creationInfo" errstr
                        ]

        ParametersFetched id fetchResult ->
            case fetchResult of
                Ok (Ok parameters) ->
                    prevModel
                        |> updateTradeParameters id parameters

                Err httpErr ->
                    UpdateResult
                        prevModel
                        Cmd.none
                        [ CmdUp.UserNotice <|
                            UN.web3FetchError "parameters" httpErr
                        ]

                Ok (Err s) ->
                    UpdateResult
                        prevModel
                        Cmd.none
                        [ CmdUp.UserNotice <|
                            UN.unexpectedError "Can't decode fetched trade parameters" s
                        ]

        StateFetched id fetchResult ->
            case fetchResult of
                Ok (Just state) ->
                    prevModel
                        |> updateTradeState id state

                _ ->
                    UpdateResult
                        prevModel
                        Cmd.none
                        [ CmdUp.UserNotice <|
                            UN.fromBadFetchResultMaybe "state" fetchResult
                        ]

        PhaseStartInfoFetched id fetchResult ->
            case fetchResult of
                Ok (Just phaseStartInfo) ->
                    prevModel
                        |> updateTradePhaseStartInfo id phaseStartInfo

                _ ->
                    UpdateResult
                        prevModel
                        Cmd.none
                        [ CmdUp.UserNotice <|
                            UN.fromBadFetchResultMaybe "phaseStartInfo" fetchResult
                        ]

        InitiatedEventDataFetched id fetchResult ->
            case fetchResult of
                Ok initiatedEventData ->
                    case CTypes.decodeTerms initiatedEventData.terms of
                        Ok terms ->
                            prevModel
                                |> updateTradeTerms id terms

                        Err e ->
                            prevModel
                                |> markTradeInvalid id

                Err e ->
                    UpdateResult
                        prevModel
                        Cmd.none
                        [ CmdUp.UserNotice <|
                            UN.unexpectedError "Error decoding initiated event" e
                        ]

        EventSentryMsg eventMsg ->
            let
                ( newEventSentry, cmd ) =
                    EventSentry.update
                        eventMsg
                        prevModel.eventSentry
            in
            UpdateResult
                { prevModel
                    | eventSentry =
                        newEventSentry
                }
                cmd
                []


updateStatus : TradeCache -> TradeCache
updateStatus tradeCache =
    let
        oldState =
            tradeCache.dataFetchState
    in
    { tradeCache
        | dataFetchState =
            { oldState
                | loaded =
                    List.length <|
                        loadedTrades tradeCache
                , invalid =
                    numInvalidTrades tradeCache
            }
    }


numInvalidTrades : TradeCache -> Int
numInvalidTrades tradeCache =
    tradeCache.trades
        |> Array.toList
        |> List.Extra.count ((==) CTypes.Invalid)


loadedTrades : TradeCache -> List CTypes.FullTradeInfo
loadedTrades tradeCache =
    tradeCache.trades
        |> Array.toList
        |> List.filterMap
            (\trade ->
                case trade of
                    CTypes.LoadedTrade fullTrade ->
                        Just fullTrade

                    _ ->
                        Nothing
            )


loadedValidTrades : TradeCache -> List CTypes.FullTradeInfo
loadedValidTrades tradeCache =
    tradeCache
        |> loadedTrades
        |> List.filter
            (\trade -> CTypes.tradeHasDefaultParameters trade.parameters)



--currently not exposed/used


loadedTradesDict : TradeCache -> Dict Int CTypes.FullTradeInfo
loadedTradesDict tradeCache =
    tradeCache.trades
        |> Array.toList
        |> List.indexedMap Tuple.pair
        |> List.filterMap
            (\( id, trade ) ->
                case trade of
                    CTypes.LoadedTrade fullTrade ->
                        Just ( id, fullTrade )

                    _ ->
                        Nothing
            )
        |> Dict.fromList


markTradeInvalid : Int -> TradeCache -> UpdateResult
markTradeInvalid id tradeCache =
    case Array.get id tradeCache.trades of
        Just trade ->
            let
                newTradeArray =
                    Array.set id
                        CTypes.Invalid
                        tradeCache.trades
            in
            UpdateResult
                ({ tradeCache | trades = newTradeArray }
                    |> updateStatus
                )
                Cmd.none
                []

        Nothing ->
            UpdateResult
                tradeCache
                Cmd.none
                [ CmdUp.UserNotice <|
                    UN.unexpectedError "markTradeInvalid ran into an out-of-range error" ( id, tradeCache.trades )
                ]


updateTradeCreationInfo : Int -> CTypes.TradeCreationInfo -> TradeCache -> ( TradeCache, List (UserNotice Msg) )
updateTradeCreationInfo id creationInfo tradeCache =
    case Array.get id tradeCache.trades of
        Just trade ->
            let
                newTrade =
                    CTypes.updateCreationInfo creationInfo trade

                newTradeArray =
                    Array.set id
                        newTrade
                        tradeCache.trades
            in
            ( { tradeCache | trades = newTradeArray }
                |> updateStatus
            , []
            )

        Nothing ->
            ( tradeCache
            , [ UN.unexpectedError "updateTradeAddress ran into an out-of-range error" ( id, tradeCache.trades ) ]
            )


updateTradeParameters : Int -> CTypes.TradeParameters -> TradeCache -> UpdateResult
updateTradeParameters id parameters tradeCache =
    case Array.get id tradeCache.trades of
        Just trade ->
            let
                newTrade =
                    CTypes.updateParameters parameters trade

                newTradeArray =
                    Array.set id
                        newTrade
                        tradeCache.trades
            in
            UpdateResult
                ({ tradeCache | trades = newTradeArray }
                    |> updateStatus
                )
                Cmd.none
                []

        Nothing ->
            UpdateResult
                tradeCache
                Cmd.none
                [ CmdUp.UserNotice <|
                    UN.unexpectedError "updateTradeParameters ran into an out-of-range error" ( id, tradeCache.trades )
                ]


updateTradePhase : Int -> CTypes.Phase -> TradeCache -> UpdateResult
updateTradePhase id newPhase tradeCache =
    case Array.get id tradeCache.trades of
        Just (CTypes.LoadedTrade trade) ->
            let
                oldState =
                    trade.state

                newTradeArray =
                    Array.set
                        id
                        (CTypes.LoadedTrade <|
                            { trade
                                | state =
                                    { oldState | phase = newPhase }
                            }
                        )
                        tradeCache.trades
            in
            UpdateResult
                ({ tradeCache | trades = newTradeArray }
                    |> updateStatus
                )
                Cmd.none
                []

        Just _ ->
            UpdateResult
                tradeCache
                Cmd.none
                [ CmdUp.UserNotice <|
                    UN.unexpectedError "updateTradePhase is trying to update a partially loaded trade" ( id, tradeCache.trades )
                ]

        Nothing ->
            UpdateResult
                tradeCache
                Cmd.none
                [ CmdUp.UserNotice <|
                    UN.unexpectedError "updateTradePhase ran into an out-of-range error" ( id, tradeCache.trades )
                ]


updateTradeState : Int -> CTypes.State -> TradeCache -> UpdateResult
updateTradeState id state tradeCache =
    case Array.get id tradeCache.trades of
        Just trade ->
            let
                newTrade =
                    CTypes.updateState state trade

                newTradeArray =
                    Array.set id
                        newTrade
                        tradeCache.trades
            in
            UpdateResult
                ({ tradeCache | trades = newTradeArray }
                    |> updateStatus
                )
                Cmd.none
                []

        Nothing ->
            UpdateResult
                tradeCache
                Cmd.none
                [ CmdUp.UserNotice <|
                    UN.unexpectedError "updateTradeState ran into an out-of-range error" ( id, tradeCache.trades )
                ]


updateTradePhaseStartInfo : Int -> CTypes.PhaseStartInfo -> TradeCache -> UpdateResult
updateTradePhaseStartInfo id phaseStartInfo tradeCache =
    case Array.get id tradeCache.trades of
        Just trade ->
            let
                newTrade =
                    CTypes.updatePhaseStartInfo phaseStartInfo trade

                newTradeArray =
                    Array.set id
                        newTrade
                        tradeCache.trades
            in
            UpdateResult
                ({ tradeCache | trades = newTradeArray }
                    |> updateStatus
                )
                Cmd.none
                []

        Nothing ->
            UpdateResult
                tradeCache
                Cmd.none
                [ CmdUp.UserNotice <|
                    UN.unexpectedError "updateTradePhaseTimeInfo ran into an out-of-range error" ( id, tradeCache.trades )
                ]


updateTradeTerms : Int -> CTypes.Terms -> TradeCache -> UpdateResult
updateTradeTerms id terms tradeCache =
    case Array.get id tradeCache.trades of
        Just trade ->
            let
                newTrade =
                    CTypes.updateTerms terms trade

                newTradeArray =
                    Array.set id
                        newTrade
                        tradeCache.trades
            in
            UpdateResult
                ({ tradeCache | trades = newTradeArray }
                    |> updateStatus
                )
                Cmd.none
                []

        Nothing ->
            UpdateResult
                tradeCache
                Cmd.none
                [ CmdUp.UserNotice <|
                    UN.unexpectedError "updateTTPaymentMethods ran into an out-of-range error" ( id, tradeCache.trades )
                ]


subscriptions : TradeCache -> Sub Msg
subscriptions tradeCache =
    Sub.batch
        [ Time.every 20000 (\_ -> CheckForNewTrades)
        , Time.every 6000 (\_ -> UpdateTradePhases)
        ]
