module Contracts.Generated.DAIHardNativeFactory exposing
    ( CreatedTrade
    , NewTrade
    , createCommittedTrade
    , createOpenTrade
    , createdTrades
    , createdTradesDecoder
    , founderFeeAddress
    , getFounderFee
    , newTradeDecoder
    , newTradeEvent
    , numTrades
    )

import Abi.Decode as AbiDecode exposing (abiDecode, andMap, data, toElmDecoder, topic)
import Abi.Encode as AbiEncode exposing (Encoding(..), abiEncode)
import BigInt exposing (BigInt)
import Eth.Types exposing (..)
import Eth.Utils as U
import Json.Decode as Decode exposing (Decoder, succeed)
import Json.Decode.Pipeline exposing (custom)



{-

   This file was generated by https://github.com/cmditch/elm-ethereum-generator

-}


{-| "createCommittedTrade(address[3],bool,uint256[7],string,string,string)" function
-}
createCommittedTrade : Address -> Address -> Address -> Address -> Bool -> BigInt -> BigInt -> BigInt -> BigInt -> BigInt -> BigInt -> BigInt -> String -> String -> String -> Call Address
createCommittedTrade contractAddress custodian beneficiary devFeeAddress initiatedByCustodian tradeAmount beneficiaryDeposit abortPunishment pokeReward autoabortInterval autoreleaseInterval devFee terms initiatorCommPubkey responderCommPubkey =
    { to = Just contractAddress
    , from = Nothing
    , gas = Nothing
    , gasPrice = Nothing
    , value = Nothing
    , data =
        Just <|
            AbiEncode.functionCall "createCommittedTrade(address[3],bool,uint256[7],string,string,string)"
                [ AbiEncode.address custodian
                , AbiEncode.address beneficiary
                , AbiEncode.address devFeeAddress
                , AbiEncode.bool initiatedByCustodian
                , AbiEncode.uint tradeAmount
                , AbiEncode.uint beneficiaryDeposit
                , AbiEncode.uint abortPunishment
                , AbiEncode.uint pokeReward
                , AbiEncode.uint autoabortInterval
                , AbiEncode.uint autoreleaseInterval
                , AbiEncode.uint devFee
                , AbiEncode.string terms
                , AbiEncode.string initiatorCommPubkey
                , AbiEncode.string responderCommPubkey
                ]
    , nonce = Nothing
    , decoder = toElmDecoder AbiDecode.address
    }


{-| "createOpenTrade(address[2],bool,uint256[8],string,string)" function
-}
createOpenTrade : Address -> Address -> Address -> Bool -> BigInt -> BigInt -> BigInt -> BigInt -> BigInt -> BigInt -> BigInt -> BigInt -> String -> String -> Call Address
createOpenTrade contractAddress initiator devFeeAddress initiatedByCustodian tradeAmount beneficiaryDeposit abortPunishment pokeReward autorecallInterval autoabortInterval autoreleaseInterval devFee terms commPubkey =
    { to = Just contractAddress
    , from = Nothing
    , gas = Nothing
    , gasPrice = Nothing
    , value = Nothing
    , data =
        Just <|
            AbiEncode.functionCall "createOpenTrade(address[2],bool,uint256[8],string,string)"
                [ AbiEncode.address initiator
                , AbiEncode.address devFeeAddress
                , AbiEncode.bool initiatedByCustodian
                , AbiEncode.uint tradeAmount
                , AbiEncode.uint beneficiaryDeposit
                , AbiEncode.uint abortPunishment
                , AbiEncode.uint pokeReward
                , AbiEncode.uint autorecallInterval
                , AbiEncode.uint autoabortInterval
                , AbiEncode.uint autoreleaseInterval
                , AbiEncode.uint devFee
                , AbiEncode.string terms
                , AbiEncode.string commPubkey
                ]
    , nonce = Nothing
    , decoder = toElmDecoder AbiDecode.address
    }


{-| "createdTrades(uint256)" function
-}
type alias CreatedTrade =
    { address_ : Address
    , blocknum : BigInt
    }


createdTrades : Address -> BigInt -> Call CreatedTrade
createdTrades contractAddress a =
    { to = Just contractAddress
    , from = Nothing
    , gas = Nothing
    , gasPrice = Nothing
    , value = Nothing
    , data = Just <| AbiEncode.functionCall "createdTrades(uint256)" [ AbiEncode.uint a ]
    , nonce = Nothing
    , decoder = createdTradesDecoder
    }


createdTradesDecoder : Decoder CreatedTrade
createdTradesDecoder =
    abiDecode CreatedTrade
        |> andMap AbiDecode.address
        |> andMap AbiDecode.uint
        |> toElmDecoder


{-| "founderFeeAddress()" function
-}
founderFeeAddress : Address -> Call Address
founderFeeAddress contractAddress =
    { to = Just contractAddress
    , from = Nothing
    , gas = Nothing
    , gasPrice = Nothing
    , value = Nothing
    , data = Just <| AbiEncode.functionCall "founderFeeAddress()" []
    , nonce = Nothing
    , decoder = toElmDecoder AbiDecode.address
    }


{-| "getFounderFee(uint256)" function
-}
getFounderFee : Address -> BigInt -> Call BigInt
getFounderFee contractAddress tradeAmount =
    { to = Just contractAddress
    , from = Nothing
    , gas = Nothing
    , gasPrice = Nothing
    , value = Nothing
    , data = Just <| AbiEncode.functionCall "getFounderFee(uint256)" [ AbiEncode.uint tradeAmount ]
    , nonce = Nothing
    , decoder = toElmDecoder AbiDecode.uint
    }


{-| "numTrades()" function
-}
numTrades : Address -> Call BigInt
numTrades contractAddress =
    { to = Just contractAddress
    , from = Nothing
    , gas = Nothing
    , gasPrice = Nothing
    , value = Nothing
    , data = Just <| AbiEncode.functionCall "numTrades()" []
    , nonce = Nothing
    , decoder = toElmDecoder AbiDecode.uint
    }


{-| "NewTrade(uint256,address,address)" event
-}
type alias NewTrade =
    { id : BigInt
    , tradeAddress : Address
    , initiator : Address
    }


newTradeEvent : Address -> Maybe Address -> LogFilter
newTradeEvent contractAddress initiator =
    { fromBlock = LatestBlock
    , toBlock = LatestBlock
    , address = contractAddress
    , topics =
        [ Just <| U.keccak256 "NewTrade(uint256,address,address)"
        , Maybe.map (abiEncode << AbiEncode.address) initiator
        ]
    }


newTradeDecoder : Decoder NewTrade
newTradeDecoder =
    succeed NewTrade
        |> custom (data 0 AbiDecode.uint)
        |> custom (data 1 AbiDecode.address)
        |> custom (topic 1 AbiDecode.address)
