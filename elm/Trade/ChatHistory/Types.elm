module Trade.ChatHistory.Types exposing (CommMessage, EncryptedMessage, Event, EventInfo(..), MessageContent(..), Model, Msg(..), StateChangeInfo(..), UpdateResult)

import CmdUp exposing (CmdUp)
import Array exposing (Array)
import CommonTypes exposing (..)
import Contracts.Types as CTypes
import Eth.Net
import Eth.Types exposing (Address)
import Helpers.Eth as EthHelpers
import Json.Decode
import Time
import Wallet


type alias Model =
    { wallet : Wallet.State
    , trade : CTypes.FullTradeInfo
    , userRole : BuyerOrSeller
    , history : Array Event
    , lastNotificationBlocknum : Int
    , messageInput : String
    }


type alias UpdateResult =
    { model : Model
    , shouldCallDecrypt : Bool
    , maybeMessageSubmit : Maybe String
    , cmdUps : List (CmdUp Msg)
    }


type Msg
    = NewEvent ( Int, CTypes.DAIHardEvent )
    | MessageInputChanged String
    | MessageSubmit
    | DecryptionFinished Json.Decode.Value


type alias Event =
    { eventInfo : EventInfo
    , blocknum : Int
    , time : Maybe Time.Posix
    }


type EventInfo
    = Statement CommMessage
    | StateChange StateChangeInfo


type alias CommMessage =
    { who : BuyerOrSeller
    , message : MessageContent
    , blocknum : Int
    }


type MessageContent
    = FailedDecode
    | Encrypted ( EncryptedMessage, EncryptedMessage )
    | FailedDecrypt
    | Decrypted String


type alias EncryptedMessage =
    { encapsulatedKey : String
    , iv : String
    , tag : String
    , message : String
    }


type StateChangeInfo
    = Initiated
    | Committed Address
    | Recalled
    | Claimed
    | Aborted
    | Released
    | Burned
