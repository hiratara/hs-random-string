{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Strict #-}
-- https://github.com/cho45/String_random.js/blob/master/lib/String_random.js
module Test.StringRandom
  ( stringRandomIO
  , stringRandom
  , stringRandomWithError
  ) where

import qualified Data.IntMap.Strict as Map
import qualified Data.Text as Text
import qualified System.Random as Random
import qualified Test.StringRandom.Parser as Parser
import qualified Control.Monad.Trans.RWS.Strict as RWS

-- Int: size, g: generater, IntMap: Record backrefs
type GenRWS g = RWS.RWS Int () (g, Map.IntMap Text.Text)

stringRandomIO :: Text.Text -> IO Text.Text
stringRandomIO txt = do
  g <- Random.newStdGen
  return $ stringRandom g txt

stringRandom :: Random.RandomGen g => g -> Text.Text -> Text.Text
stringRandom g txt = case stringRandomWithError g txt of
                       Left  l -> error l
                       Right r -> r

stringRandomWithError :: Random.RandomGen g => g -> Text.Text -> Either String Text.Text
stringRandomWithError g txt = do
  parsed <- Parser.processParse txt
  -- 10 : max length of a* or a+
  let (ret, _) = RWS.evalRWS (str parsed) 10 (g, Map.empty)
  return ret

withGen :: Random.RandomGen g => (g -> (a, g)) -> GenRWS g a
withGen f = do
  (gen, m) <- RWS.get
  let (a, gen') = f gen
  RWS.put (gen', m)
  return a

randomRM :: (Random.RandomGen g, Random.Random a) => (a, a) -> GenRWS g a
randomRM = withGen . Random.randomR

-- randomM :: (Random.RandomGen g, Random.Random a) => GenRWS g a
-- randomM = withGen Random.random

choice :: Random.RandomGen g => [a] -> GenRWS g a
choice xs = do
  i <- randomRM (0, length xs - 1)
  return $ xs !! i

putGroup :: Int -> Text.Text -> GenRWS g ()
putGroup n v = do
  (gen, m) <- RWS.get
  let m' = Map.insert n v m
  RWS.put (gen, m')

getGroup :: Int -> GenRWS g Text.Text
getGroup n = do
  m <- RWS.gets snd
  let maybeV = Map.lookup n m
  case maybeV of
    Nothing -> return ""
    Just v  -> return v

size :: GenRWS g Int
size = RWS.ask

str :: Random.RandomGen g => Parser.Parsed -> GenRWS g Text.Text
str (Parser.PClass cs) = Text.singleton <$> choice cs
str (Parser.PRange s me p) = do
  e <- case me of
    Just e' -> return e'
    Nothing -> size
  n <- randomRM (s, e)
  Text.concat <$> mapM (const $ str p) [1 .. n]
str (Parser.PConcat ps) = Text.concat <$> mapM str ps
str (Parser.PSelect ps) = str =<< choice ps
str (Parser.PGrouped n p) = do
  v <- str p
  putGroup n v
  return v
str (Parser.PBackward n) = getGroup n
str (Parser.PIgnored) = return ""
