{-# LANGUAGE OverloadedStrings #-}

module Explorer.Web.Api.Legacy.BlocksTxs
  ( blocksTxs

  -- For testing:
  , queryBlocksTxs
  ) where

import Cardano.Db
    ( DbLovelace (..), EntityField (..), TxId, unValue3 )
import Control.Monad.IO.Class
    ( MonadIO )
import Data.ByteString.Char8
    ( ByteString )
import Data.Int
    ( Int64 )
import Data.List.Extra
    ( groupOn )
import Data.Maybe
    ( fromMaybe )
import Data.Text
    ( Text )
import Data.Time.Clock
    ( UTCTime )
import Data.Word
    ( Word16 )
import Database.Esqueleto
    ( InnerJoin (..)
    , Value (..)
    , distinct
    , from
    , in_
    , on
    , select
    , val
    , valList
    , where_
    , (&&.)
    , (==.)
    , (^.)
    )
import Database.Persist.Sql
    ( SqlPersistT )
import Explorer.Web.Api.Legacy.Util
    ( bsBase16Encode
    , collapseTxGroup
    , genesisDistributionTxHash
    , textBase16Decode
    , zipTxBrief
    )
import Explorer.Web.ClientTypes
    ( CAddress (..)
    , CHash (..)
    , CTxAddressBrief (..)
    , CTxBrief (..)
    , CTxHash (..)
    )
import Explorer.Web.Error
    ( ExplorerError (..) )

-- Example queries:
--
--  /api/blocks/txs/not-valid
--  /api/blocks/txs/d30117e2e488cb3f496a47305eee3c8ea01e83e9e91e2719f1677de07f902e9a
--  /api/blocks/txs/c25f5468195e95dc6e7acbc0f0da794113b0edbfe1f998e10c85e2a1ec679e83
--  /api/blocks/txs/e22e8771de60d44820c72b10114a7aee7cf98e3b188936e8601f9a12637edf63
--  /api/blocks/txs/619457f25781b1c32c935e711a019d8c584574b363b27f3ae1393bddb895017a

blocksTxs
    :: MonadIO m
    => CHash
    -> Maybe Int64
    -> Maybe Int64
    -> SqlPersistT m (Either ExplorerError [CTxBrief])
blocksTxs (CHash blkHashTxt) mLimit mOffset =
    case textBase16Decode blkHashTxt of
      Left err -> pure $ Left err
      Right blkHash -> queryBlocksTxs blkHash pageSize page
  where
    pageSize = fromMaybe 10 mLimit
    page = fromMaybe 0 mOffset


queryBlocksTxs :: MonadIO m => ByteString -> Int64 -> Int64 -> SqlPersistT m (Either ExplorerError [CTxBrief])
queryBlocksTxs blkHash _limitNum _offsetNum  = do
    res <- select . from $ \  (blk `InnerJoin` tx) -> do
            on (blk ^. BlockId ==. tx ^. TxBlockId)
            where_ (blk ^. BlockHash ==. val blkHash)
            -- limit limitNum
            -- offset offsetNum
            pure (tx ^. TxId, tx ^. TxHash, blk ^. BlockTime)
    case map unValue3 res of
      [] -> pure $ Left (Internal "No block found")
      xs -> Right <$> queryCTxBriefs xs

queryCTxBriefs :: MonadIO m => [(TxId, ByteString, UTCTime)] -> SqlPersistT m [CTxBrief]
queryCTxBriefs [] = pure []
queryCTxBriefs xs = do
  let txids = map fst3 xs
  zipTxBrief xs <$> queryTxInputs txids <*> queryTxOutputs txids

queryTxInputs :: MonadIO m => [TxId] -> SqlPersistT m [(TxId, [CTxAddressBrief])]
queryTxInputs txids = do
    rows <- select . distinct . from $ \(tx `InnerJoin` txIn `InnerJoin` txOut `InnerJoin` txInTx) -> do
              on (tx ^. TxId ==. txIn ^. TxInTxInId)
              on (txIn ^. TxInTxOutId ==. txOut ^. TxOutTxId &&. txIn ^. TxInTxOutIndex ==. txOut ^. TxOutIndex)
              on (txOut ^. TxOutTxId ==. txInTx ^. TxId)
              where_ (txIn ^. TxInTxInId `in_` valList txids)
              pure (tx ^. TxId, txOut ^. TxOutAddress, txOut ^. TxOutValue, txInTx ^. TxHash, txOut ^. TxOutIndex, txInTx ^. TxSize ==. val 0)
    pure $ map collapseTxGroup (groupOn fst $ map convert rows)
  where
    convert :: (Value TxId, Value Text, Value DbLovelace, Value ByteString, Value Word16, Value Bool) -> (TxId, CTxAddressBrief)
    convert (Value txid, Value addr, Value coin, Value txh, Value index, Value isGenesisTx) =
      ( txid
      , if isGenesisTx
          then
            CTxAddressBrief
              { ctaAddress = CAddress addr
              , ctaAmount = fromIntegral $ unDbLovelace coin
              , ctaTxHash = genesisDistributionTxHash
              , ctaTxIndex = 0
              }
          else
            CTxAddressBrief
              { ctaAddress = CAddress addr
              , ctaAmount = fromIntegral $ unDbLovelace coin
              , ctaTxHash = CTxHash $ CHash (bsBase16Encode txh)
              , ctaTxIndex = fromIntegral index
              }
      )

queryTxOutputs :: MonadIO m => [TxId] -> SqlPersistT m [(TxId, [CTxAddressBrief])]
queryTxOutputs txids = do
    rows <- select . from $ \ (tx `InnerJoin` txOut) -> do
              on (tx ^. TxId ==. txOut ^. TxOutTxId)
              where_ (tx ^. TxId `in_` valList txids)
              pure (tx ^. TxId, txOut ^. TxOutAddress, txOut ^. TxOutValue, tx ^. TxHash, txOut ^. TxOutIndex)
    pure $ map collapseTxGroup (groupOn fst $ map convert rows)
  where
    convert :: (Value TxId, Value Text, Value DbLovelace, Value ByteString, Value Word16) -> (TxId, CTxAddressBrief)
    convert (Value txid, Value addr, Value coin, Value txhash, Value index) =
      ( txid
      , CTxAddressBrief
          { ctaAddress = CAddress addr
          , ctaAmount = fromIntegral $ unDbLovelace coin
          , ctaTxHash = CTxHash . CHash $ bsBase16Encode txhash
          , ctaTxIndex = fromIntegral index
          }
      )

-- -------------------------------------------------------------------------------------------------

fst3 :: (a, b, c) -> a
fst3 (a, _, _) = a
