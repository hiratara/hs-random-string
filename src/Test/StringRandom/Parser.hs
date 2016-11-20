{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Strict #-}
-- https://github.com/cho45/String_random.js/blob/master/lib/String_random.js
module Test.StringRandom.Parser
  ( Parsed(..)
  , processParse
  ) where

import qualified Data.Attoparsec.Text as Attoparsec
import Data.Attoparsec.Text
  ( char
  , anyChar
  , satisfy
  , string
  , digit
  , many1
  , endOfInput
  )
import qualified Data.Text as Text
import Control.Applicative ((<|>), optional, many)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.State.Strict (evalStateT, StateT, gets, put)

-- Int :: A sequence number of groups (X)
type RegParser a = StateT Int Attoparsec.Parser a

data Parsed  = PClass   [Char]               -- [abc]
             | PNClass  [Char]               -- [^abc]
             | PRange Int (Maybe Int) Parsed -- X*, X{1,2}, X+, X?
             | PConcat [Parsed]              -- XYZ
             | PSelect [Parsed]              -- X|Y|Z
             | PGrouped Int Parsed           -- (X)
             | PIgnored                      -- ^, $, \b
             deriving (Show, Eq)

pConcat :: [Parsed] -> Parsed
pConcat [x] = x
pConcat xs  = PConcat xs

pSelect :: [Parsed] -> Parsed
pSelect [x] = x
pSelect xs  = PSelect xs

processParse :: Text.Text -> Either String Parsed
processParse = let p = evalStateT selectParser 0
               in Attoparsec.parseOnly (p <* endOfInput)

selectParser :: RegParser Parsed
selectParser = do
  p0 <- concats
  ps <- many (lift (char '|') *> concats)
  return $ pSelect (p0:ps)
  where
    concats = pConcat <$> many rangedParser

rangedParser :: RegParser Parsed
rangedParser = do
  p <- groupingParser
  let opt  = char '?' *> return (PRange 0 (Just 1) p)
      star = char '*' *> return (PRange 0 Nothing p)
      plus = char '+' *> return (PRange 1 Nothing p)
      rep = char '{' *> (rep1 <|> rep2) <* char '}'
      rep1 = do
        min  <- read <$> many1 digit
        max' <- optional $ char ',' *> many digit
        let max = case max' of
                    Nothing -> Just min
                    Just [] -> Nothing
                    Just ds -> Just $ read ds
        return $ PRange min max p
      rep2 = do
        max' <- char ',' *> many digit
        let max = case max' of
                    [] -> Nothing
                    _  -> Just $ read max'
        return $ PRange 0 max p
  lift $ opt <|> star <|> plus <|> rep <|> return p

groupingParser :: RegParser Parsed
groupingParser = ngroup <|> group <|> classParser <|> escaped <|> dot <|> ignored <|> others
  where
    ngroup  = lift (string "(?:") *> selectParser <* lift (char ')')
    group   = do
      n <- gets (+ 1)
      put n
      p <- lift (char '(') *> selectParser <* lift (char ')')
      return $ PGrouped n p
    escaped = lift $ do
      ch <- char '\\' *> anyChar
      return $ case ch of
        'b' -> PIgnored -- Don't support \b
        _   -> PClass (classes ch)
    dot     = lift $ char '.' *> return (PClass allC)
    ignored = lift $ satisfy (`elem` ['^', '$']) *> return PIgnored
    others  = lift $ PClass . (: [])  <$> satisfy (`notElem` reservedChars)

classParser :: RegParser Parsed
classParser = lift $
      PNClass <$> (string "[^" *> p <* char ']')
  <|> PClass  <$> (char '[' *> p <* char ']')
  where
    p :: Attoparsec.Parser [Char]
    p = concat <$> many p1
    p1 = do
      ch <- onechar
      r  <- optional (char '-' *> onechar)
      return $ case r of
        Just rch
          | length ch == 1 && length rch == 1
            -> enumFromTo (head ch) (head rch)
          -- Handle the case of [^\w-\d]
          | otherwise
            -> ch ++ '-' : rch
        Nothing -> ch
    onechar =  classes <$> (char '\\' *> anyChar)
           <|> (: [])  <$> satisfy (`notElem` classReservedChars)

uppersC, lowersC, digitsC, spacesC, othersC, allC :: [Char]
uppersC = ['A'..'Z']
lowersC = ['a'..'z']
digitsC = ['0'..'9']
spacesC = " \n\t"
othersC = "!\"#$%&'()*+,-./:;<=>?@[\\]^`{|}~"
allC    = concat [uppersC, lowersC, digitsC, " ", othersC, "_"]

classes :: Char -> [Char]
classes 'd' = digitsC
classes 'D' = concat [uppersC, lowersC, spacesC, othersC, "_"]
classes 'w' = concat [uppersC, lowersC, digitsC, "_"]
classes 'W' = concat [spacesC, othersC]
classes 't' = "\t"
classes 'n' = "\n"
classes 'v' = "\x000b"
classes 'f' = "\x000c"
classes 'r' = "\r"
classes 's' = spacesC
classes 'S' = concat [uppersC, lowersC, digitsC, othersC, "_"]
classes '0' = "\0"
classes c   = [c]

reservedChars :: [Char]
reservedChars = "\\()|^$*+{?[." -- ]

classReservedChars :: [Char]
classReservedChars = "\\]" -- -^
