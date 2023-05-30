module Trade.ChatHistory.State exposing (handleNewEvent, init, update)

import CmdUp exposing (CmdUp)
import Array exposing (Array)
import CommonTypes exposing (..)
import Contracts.Types as CTypes
import Eth
import Helpers.Eth as EthHelpers
import Json.Decode
import Json.Encode
import Maybe.Extra
import Trade.ChatHistory.SecureComm exposing (..)
import Trade.ChatHistory.Types exposing (..)
import UserNotice as UN
import Wallet


init : Wallet.State -> BuyerOrSeller -> CTypes.FullTradeInfo -> List ( Int, CTypes.DAIHardEvent ) -> Int -> ( Model, Bool, List (CmdUp Msg) )
init wallet userRole trade initialEvents currentBlocknum =
    Model
        wallet
        trade
        userRole
        Array.empty
        currentBlocknum
        ""
        |> handleInitialEvents initialEvents


update : Msg -> Model -> UpdateResult
update msg prevModel =
    case msg of
        NewEvent ( blocknum, event ) ->
            let
                ( newModel, shouldCallDecrypt, cmdUps ) =
                    handleNewEvent blocknum event prevModel
            in
            UpdateResult
                newModel
                shouldCallDecrypt
                Nothing
                cmdUps

        MessageInputChanged newMessageStr ->
            UpdateResult
                { prevModel | messageInput = newMessageStr }
                False
                Nothing
                []

        MessageSubmit ->
            UpdateResult
                { prevModel | messageInput = "" }
                False
                (Just prevModel.messageInput)
                []

        DecryptionFinished decryptedMessageValue ->
            case decodeDecryptionResult decryptedMessageValue of
                Ok ( id, message ) ->
                    case Array.get id prevModel.history of
                        Just historyEvent ->
                            case historyEvent.eventInfo of
                                Statement commMessage ->
                                    let
                                        newCommMessage =
                                            { commMessage
                                                | message = Decrypted message
                                            }

                                        newHistoryEvent =
                                            { historyEvent
                                                | eventInfo = Statement newCommMessage
                                            }

                                        newHistory =
                                            Array.set id newHistoryEvent prevModel.history
                                    in
                                    UpdateResult
                                        { prevModel | history = newHistory }
                                        False
                                        Nothing
                                        []

                                _ ->
                                    UpdateResult
                                        prevModel
                                        False
                                        Nothing
                                        [ CmdUp.UserNotice <|
                                            UN.unexpectedError "got a decryption result, but for an event that is not a message!" historyEvent
                                        ]

                        Nothing ->
                            UpdateResult
                                prevModel
                                False
                                Nothing
                                [ CmdUp.UserNotice <|
                                    UN.unexpectedError "got a decryption result, but for an id out of bounds!" ( id, prevModel.history )
                                ]

                Err s ->
                    UpdateResult
                        prevModel
                        False
                        Nothing
                        [ CmdUp.UserNotice <|
                            UN.unexpectedError "Error decoding decryption result" s
                        ]


handleInitialEvents : List ( Int, CTypes.DAIHardEvent ) -> Model -> ( Model, Bool, List (CmdUp Msg) )
handleInitialEvents initialEvents prevModel =
    let
        helper : List ( Int, CTypes.DAIHardEvent ) -> ( Model, Bool, List (CmdUp Msg) ) -> ( Model, Bool, List (CmdUp Msg) )
        helper events ( model, shouldDecrypt, cmdUps ) =
            case events of
                [] ->
                    ( model, shouldDecrypt, cmdUps )

                ( blocknum, event ) :: remainingEvents ->
                    let
                        ( thisModel, thisShouldDecrypt, newCmdUps ) =
                            handleNewEvent blocknum event model
                    in
                    helper remainingEvents ( thisModel, shouldDecrypt || thisShouldDecrypt, List.append cmdUps newCmdUps )
    in
    helper initialEvents ( prevModel, False, [] )


handleNewEvent : Int -> CTypes.DAIHardEvent -> Model -> ( Model, Bool, List (CmdUp Msg) )
handleNewEvent blocknum event prevModel =
    let
        toBuyerOrSeller =
            CTypes.initiatorOrResponderToBuyerOrSeller prevModel.trade.parameters.initiatorRole

        maybeHistoryEventInfo =
            case event of
                CTypes.InitiatedEvent _ ->
                    Just <| StateChange Initiated

                CTypes.CommittedEvent data ->
                    Just <| StateChange (Committed data.responder)

                CTypes.RecalledEvent ->
                    Just <| StateChange Recalled

                CTypes.ClaimedEvent ->
                    Just <| StateChange Claimed

                CTypes.AbortedEvent ->
                    Just <| StateChange Aborted

                CTypes.ReleasedEvent ->
                    Just <| StateChange Released

                CTypes.BurnedEvent ->
                    Just <| StateChange Burned

                CTypes.InitiatorStatementLogEvent data ->
                    Just <|
                        Statement <|
                            { who = Initiator |> toBuyerOrSeller
                            , message =
                                case decodeEncryptedMessages data.statement of
                                    Just decodedMessages ->
                                        Encrypted decodedMessages

                                    _ ->
                                        FailedDecode
                            , blocknum = blocknum
                            }

                CTypes.ResponderStatementLogEvent data ->
                    Just <|
                        Statement <|
                            { who = Responder |> toBuyerOrSeller
                            , message =
                                case decodeEncryptedMessages data.statement of
                                    Just decodedMessages ->
                                        Encrypted decodedMessages

                                    _ ->
                                        FailedDecode
                            , blocknum = blocknum
                            }

                CTypes.PokeEvent ->
                    Nothing

        ( maybeNotifyCmdUp, newLastNotificationBlocknum ) =
            if blocknum > prevModel.lastNotificationBlocknum then
                ( maybeHistoryEventInfo
                    |> Maybe.map
                        (historyEventToBrowserNotifcationCmdUp
                            (prevModel.userRole == prevModel.trade.parameters.initiatorRole)
                        )
                , blocknum
                )

            else
                ( Nothing
                , prevModel.lastNotificationBlocknum
                )

        maybeNewEvent =
            Maybe.map
                (\historyEventInfo ->
                    { eventInfo = historyEventInfo
                    , blocknum = blocknum
                    , time = Nothing
                    }
                )
                maybeHistoryEventInfo

        newHistory =
            Array.append
                prevModel.history
                (Array.fromList <|
                    Maybe.Extra.values [ maybeNewEvent ]
                )

        newModel =
            { prevModel
                | history = newHistory
                , lastNotificationBlocknum = newLastNotificationBlocknum
            }
    in
    ( newModel
    , case maybeHistoryEventInfo of
        Just (Statement _) ->
            True

        _ ->
            False
    , Maybe.Extra.values [ maybeNotifyCmdUp ]
    )


historyEventToBrowserNotifcationCmdUp : Bool -> EventInfo -> CmdUp Msg
historyEventToBrowserNotifcationCmdUp userIsInitiator event =
    case event of
        Statement commMessage ->
            CmdUp.BrowserNotification
                "New Message from Trade"
                Nothing
                Nothing

        StateChange stateChangeInfo ->
            let
                str =
                    case stateChangeInfo of
                        Initiated ->
                            "Trade Opened."

                        Committed _ ->
                            if userIsInitiator then
                                "Someone has committed to the Trade!"

                            else
                                "You are now committed to the Trade!"

                        Recalled ->
                            "Trade recalled."

                        Claimed ->
                            "Payment has been confirmed by the Buyer."

                        Aborted ->
                            "Trade aborted by Buyer."

                        Released ->
                            "Trade released by Seller."

                        Burned ->
                            "Trade burned by Seller."
            in
            CmdUp.BrowserNotification
                str
                Nothing
                Nothing
