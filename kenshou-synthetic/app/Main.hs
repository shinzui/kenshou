module Main (main) where

import Kenshou.Cli (mainWith)
import Kenshou.Suite.Synthetic (syntheticProgram)

main :: IO ()
main = mainWith syntheticProgram
