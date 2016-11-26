{-# LANGUAGE Strict #-}
module Main (main) where

import Data.Monoid ((<>))
import qualified Options.Applicative as Options
import qualified Data.Text as Text
import qualified Data.Text.IO as Text
import qualified Text.StringRandom as StringRandom
import qualified System.Random.PCG as PCG

argParser :: Options.Parser Text.Text
argParser = Text.pack <$> Options.strArgument
         ( Options.metavar "REGEXP"
        <> Options.help "Regexp as a template (e.g. '[1-3]{2}random[!?]')"
         )

main :: IO ()
main = do
  pat <- Options.execParser opts
  gen <- PCG.save =<< PCG.createSystemRandom
  let txt = StringRandom.stringRandom gen pat
  Text.putStrLn txt
  where
    opts = Options.info (Options.helper <*> argParser)
      ( Options.fullDesc
     <> Options.header "hstrrand - Generate string which matches REGEXP" )
