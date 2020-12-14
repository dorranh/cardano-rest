{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Wno-error=partial-fields #-}

-- | Types that arise in the API: mostly simplified representations
-- of the core types which are easier to serialize.
-- Used in purescript-bridge.

module Explorer.Web.ClientTypes
       ( CHash (..)
       , CAddress (..)
       , CTxHash (..)
       , CBlockEntry (..)
       , CTxEntry (..)
       , CBlockSummary (..)
       , CAddressType (..)
       , CChainTip (..)
       , CTxAddressBrief (..)
       , CTxMeta (..)
       , CAddressSummary (..)
       , CAddressBalanceError (..)
       , CTxBrief (..)
       , CUtxo  (..)
       , CNetworkAddress (..)
       , CNetwork (..)
       , CAddressBalance (..)
       , CTxSummary (..)
       , CGenesisSummary (..)
       , CGenesisAddressInfo (..)
       , CAddressesFilter (..)
       , CCoin(..)
       , CByteString (..)
       , toCHash
       , adaToCCoin
       , cCoinToAda
       ) where

import Cardano.Crypto.Hash.Class
    ( Hash, hashToTextAsHex )
import Cardano.Db
    ( Ada (..) )
import Control.DeepSeq
    ( NFData )
import Control.Monad.Error.Class
    ( throwError )
import Data.Aeson.TH
    ( defaultOptions, deriveJSON, deriveToJSON )
import Data.Aeson.Types
    ( ToJSON (toJSON), Object)
import Data.ByteString
    ( ByteString )
import Data.Fixed
    ( Fixed (..) )
import Data.Hashable
    ( Hashable )
import Data.Text
    ( Text )
import Data.Time.Clock.POSIX
    ( POSIXTime )
import Data.Word
    ( Word16, Word64 )
import Formatting
    ( Buildable, build, sformat, (%) )
import GHC.Generics
    ( Generic )
import Servant.API
    ( FromHttpApiData (parseUrlPiece) )

import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Base16 as B16
import qualified Data.ByteString.Char8 as B8
import qualified Data.Text as T

-------------------------------------------------------------------------------------
-- Hash types
-------------------------------------------------------------------------------------

-- See this page for more explanation - https://cardanodocs.com/cardano/addresses/
-- We have the general type @AbstractHash@ for all hashes we use. It's being parametrized
-- by two types - AbstractHash algo a - the hashing algorithm and the phantom type for
-- extra safety (can be a @Tx@, an @Address@ and so on, ...).
--
-- The following types explain the situation better:
--
-- type AddressHash   = AbstractHash Blake2b_224
-- type Hash          = AbstractHash Blake2b_256
--
-- type TxId          = Hash Tx               = AbstractHash Blake2b_256 Tx
-- type StakeholderId = AddressHash PublicKey = AbstractHash Blake2b_224 PublicKey
--
-- From there on we have the client types that we use to represent the actual hashes.
-- The client types are really the hash bytes converted to Base16 address.

-- | Client hash
-- TODO, make it ByteString internally, and have FromHttpApiData/ToJSON translate to hex?
newtype CHash = CHash Text
  deriving (Show, Eq, Generic, Buildable, Hashable, NFData)

-- | Client address. The address from Cardano
newtype CAddress
    = CAddress { unCAddress :: Text }
    deriving (Show, Eq, Generic, Ord, Buildable, Hashable, NFData)

instance ToJSON CAddress where
    toJSON (CAddress txt) = Aeson.String txt

-- | Client transaction id
newtype CTxHash = CTxHash CHash
    deriving (Show, Eq, Generic, Buildable, Hashable, NFData)

-- | The network, eg "mainnet", "testnet" etc
newtype CNetwork = CNetwork Text
    deriving (Show, Eq, Generic, Buildable, Hashable, NFData)

-------------------------------------------------------------------------------------
-- Composite types
-------------------------------------------------------------------------------------

-- | CCoin denominated in Lovelace (for compatibility with the old explorer-webapi).
newtype CCoin = CCoin
    { unCCoin :: Integer
    } deriving (Show, Generic, Eq)
      deriving newtype (Num, Ord)

instance ToJSON CCoin where
  toJSON (CCoin coin) = Aeson.object [ ("getCoin", Aeson.String (T.pack $ show coin)) ]

adaToCCoin :: Ada -> CCoin
adaToCCoin (Ada (MkFixed ll)) = CCoin ll

cCoinToAda :: CCoin -> Ada
cCoinToAda (CCoin ll) = Ada (MkFixed ll)

-- | List of block entries is returned from "get latest N blocks" endpoint
data CBlockEntry = CBlockEntry
    { cbeEpoch      :: !Word64
    , cbeSlot       :: !Word64
    , cbeBlkHeight  :: !Word
    , cbeBlkHash    :: !CHash
    , cbeTimeIssued :: !(Maybe POSIXTime)
    , cbeTxNum      :: !Word
    , cbeTotalSent  :: !CCoin
    , cbeSize       :: !Word64
    , cbeBlockLead  :: !(Maybe Text)
    , cbeFees       :: !CCoin
    } deriving (Show, Generic, Eq)

-- | List of tx entries is returned from "get latest N transactions" endpoint
data CTxEntry = CTxEntry
    { cteId         :: !CTxHash
    , cteTimeIssued :: !(Maybe POSIXTime)
    , cteAmount     :: !CCoin
    } deriving (Show, Generic)


-- | Data displayed on block summary page
data CBlockSummary = CBlockSummary
    { cbsEntry      :: !CBlockEntry
    , cbsPrevHash   :: !CHash
    , cbsNextHash   :: !(Maybe CHash)
    , cbsMerkleRoot :: !CHash
    } deriving (Show, Generic)

data CAddressType
    = CPubKeyAddress
    | CRedeemAddress
    deriving (Show, Generic)

data CAddressSummary = CAddressSummary
    { caAddress :: !CAddress
    , caType    :: !CAddressType
    , caChainTip :: !CChainTip
    , caTxNum   :: !Word
    , caBalance :: !CCoin
    , caTotalInput :: !CCoin
    , caTotalOutput :: !CCoin
    , caTotalFee :: !CCoin
    , caTxList  :: ![CTxBrief]
    } deriving (Show, Generic)

data CChainTip = CChainTip
    { ctBlockNo :: !Word
    , ctSlotNo :: !Word
    , ctBlockHash :: !CHash
    } deriving (Show, Generic)

data CTxBrief = CTxBrief
    { ctbId         :: !CTxHash
    , ctbTimeIssued :: !(Maybe POSIXTime)
    , ctbInputs     :: ![CTxAddressBrief]
    , ctbOutputs    :: ![CTxAddressBrief]
    , ctbInputSum   :: !CCoin
    , ctbOutputSum  :: !CCoin
    , ctbFees       :: !CCoin
    } deriving (Eq, Generic, Show)

data CTxAddressBrief = CTxAddressBrief
    { ctaAddress :: !CAddress
    , ctaAmount :: !CCoin
    , ctaTxHash :: !CTxHash
    , ctaTxIndex :: !Word
    } deriving (Eq, Generic, Show)

data CUtxo = CUtxo
    { cuId       :: !CTxHash
    , cuOutIndex :: !Int
    , cuAddress  :: !CAddress
    , cuCoins    :: !CCoin
    } deriving (Show, Generic)

newtype CNetworkAddress = CNetworkAddress Text
    deriving (Show, Generic)

data CTxSummary = CTxSummary
    { ctsId              :: !CTxHash
    , ctsTxTimeIssued    :: !(Maybe POSIXTime)
    , ctsBlockTimeIssued :: !(Maybe POSIXTime)
    , ctsBlockHeight     :: !(Maybe Word)
    , ctsBlockEpoch      :: !(Maybe Word64)
    , ctsBlockSlot       :: !(Maybe Word64)
    , ctsBlockHash       :: !(Maybe CHash)
    , ctsRelayedBy       :: !(Maybe CNetworkAddress)
    , ctsTotalInput      :: !CCoin
    , ctsTotalOutput     :: !CCoin
    , ctsFees            :: !CCoin
    , ctsInputs          :: ![CTxAddressBrief]
    , ctsOutputs         :: ![CTxAddressBrief]
    } deriving (Show, Generic)

data CTxMeta = CTxMeta 
    { ctmTxId :: !CTxHash
    , ctmJSON :: !Object
    } deriving (Show, Generic)

data CGenesisSummary = CGenesisSummary
    { cgsNumTotal               :: !Word
    , cgsNumRedeemed            :: !Word
    , cgsNumNotRedeemed         :: !Word
    , cgsRedeemedAmountTotal    :: !CCoin
    , cgsNonRedeemedAmountTotal :: !CCoin
    } deriving (Show, Generic)

data CGenesisAddressInfo = CGenesisAddressInfo
    { cgaiCardanoAddress :: !CAddress
    , cgaiGenesisAmount  :: !CCoin
    , cgaiIsRedeemed     :: !Bool
    } deriving (Show, Generic)

data CAddressesFilter
    = RedeemedAddresses
    | NonRedeemedAddresses
    | AllAddresses
    deriving (Show, Generic)

-- This is not part of the original explorer and we need to match the http-bridge's
-- generated JSON, so we need a data type using standard data types and need a custom
-- hand rolled ToJSON instance.
data CAddressBalance = CAddressBalance
    { cuaAddress :: !Text
    , cuaTxHash :: !Text
    , cuaIndex :: !Word16
    , cuaCoin :: !Word64
    } deriving (Show)

-- | Basically an 'Either' used in place of an 'Either' to avoid overlapping
-- instances.
data CAddressBalanceError
    = CABError !Text
    | CABValue ![CAddressBalance]
    deriving (Show)

instance ToJSON CAddressBalance where
    toJSON cua =
      Aeson.object
        [ ( "address", toJSON (cuaAddress cua) )
        , ( "txid", toJSON (cuaTxHash cua) )
        , ( "index", toJSON (cuaIndex cua) )
        , ( "coin", toJSON (cuaCoin cua) )
        ]

instance ToJSON CAddressBalanceError where
    toJSON cab =
      case cab of
        CABError err -> Aeson.String err
        CABValue val -> toJSON val

--------------------------------------------------------------------------------
-- FromHttpApiData instances
--------------------------------------------------------------------------------

toCHash :: Hash h a -> CHash
toCHash = CHash . hashToTextAsHex

instance FromHttpApiData CHash where
    parseUrlPiece url = case B16.decode (B8.pack (T.unpack url)) of
          (_, "") -> Right $ CHash url
          _       -> Left "invalid hash"

instance FromHttpApiData CAddress where
    parseUrlPiece = pure . CAddress

instance FromHttpApiData CTxHash where
    parseUrlPiece = pure . CTxHash . CHash

instance FromHttpApiData CNetwork where
    parseUrlPiece = pure . CNetwork

instance FromHttpApiData CAddressesFilter where
    parseUrlPiece "all" = pure AllAddresses
    parseUrlPiece "redeemed" = pure RedeemedAddresses
    parseUrlPiece "notredeemed" = pure NonRedeemedAddresses
    parseUrlPiece other = throwError $
        sformat ("Unknown option '"%build%"'. "%
            "Valid options are 'all', 'redeemed' and 'notredeemed'.") other

-- TODO: When we have a generic enough `readEither`
-- instance FromHttpApiData LocalSlotIndex where
--     parseUrlPiece = readEither

newtype CByteString = CByteString ByteString
    deriving (Generic)

instance Show CByteString where
    show (CByteString bs) = (show . B16.encode) bs

deriveJSON defaultOptions ''CHash
deriveJSON defaultOptions ''CTxHash

deriveToJSON defaultOptions ''CBlockEntry
deriveToJSON defaultOptions ''CTxEntry
deriveToJSON defaultOptions ''CTxBrief
deriveToJSON defaultOptions ''CAddressType
deriveToJSON defaultOptions ''CAddressSummary
deriveToJSON defaultOptions ''CBlockSummary
deriveToJSON defaultOptions ''CNetworkAddress
deriveToJSON defaultOptions ''CChainTip
deriveToJSON defaultOptions ''CTxSummary
deriveToJSON defaultOptions ''CTxMeta
deriveToJSON defaultOptions ''CTxAddressBrief
deriveToJSON defaultOptions ''CGenesisSummary
deriveToJSON defaultOptions ''CGenesisAddressInfo
deriveToJSON defaultOptions ''CUtxo

instance ToJSON CByteString where
    toJSON (CByteString bs) = (toJSON . show . B16.encode) bs
